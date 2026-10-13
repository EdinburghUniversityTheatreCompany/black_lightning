module Graph
  # Graph client for one shared mailbox (app-only auth; Exchange scopes the Entra app to named
  # mailboxes). The reimbursements receipt mailbox and the climate CSV mailbox are both
  # instances, differing only in address. It polls rather than using ActionMailbox because
  # Microsoft 365 has no inbound webhook.
  class MailboxClient
    include ::GraphAuth

    FOLDERS = { processed: "Processed", rejected: "Rejected" }.freeze
    PAGE_SIZE = 20

    Message = Struct.new(:id, :from_address, :subject, :body_text, keyword_init: true)

    def initialize(mailbox:, settings: Graph::Settings, http: nil, clock: nil, sleeper: nil)
      @mailbox = mailbox
      @settings = settings
      @http = http || ::HttpTransport
      @clock = clock || -> { Time.current }
      @sleeper = sleeper
      @folder_ids = {}
    end

    def unread_messages
      response = graph_request(:get, "/users/#{@mailbox}/mailFolders/inbox/messages",
                         params: { "$filter" => "isRead eq false",
                                   "$select" => "id,subject,from,bodyPreview",
                                   "$top" => PAGE_SIZE })
      response.fetch("value").map do |raw|
        Message.new(
          id: raw["id"],
          from_address: raw.dig("from", "emailAddress", "address").to_s.downcase,
          subject: raw["subject"].to_s,
          body_text: raw["bodyPreview"].to_s
        )
      end
    end

    # Inline images count too (signature logos are rare enough to ignore). Only attached mail
    # items (forwards) are skipped.
    def attachments(message_id)
      response = graph_request(:get, "/users/#{@mailbox}/messages/#{message_id}/attachments")
      response.fetch("value").filter_map do |attachment|
        next unless attachment["@odata.type"] == "#microsoft.graph.fileAttachment"
        next if attachment["contentBytes"].blank?

        { filename: attachment["name"].to_s,
          content_type: attachment["contentType"].to_s,
          bytes: Base64.decode64(attachment["contentBytes"]) }
      end
    end

    def reply(message_id, html:)
      return nil unless outbound?

      graph_request(:post, "/users/#{@mailbox}/messages/#{message_id}/reply",
              body: { comment: html })
      nil
    rescue NotFoundError => e
      swallow_only_if_gone(message_id, "reply", e)
    end

    # The idempotency commit point: unread_messages never re-fetches a read message. Separate
    # from +move+ so a move failure never leaves it unread.
    def mark_read(message_id)
      return nil unless outbound?

      graph_request(:patch, "/users/#{@mailbox}/messages/#{message_id}", body: { isRead: true })
      nil
    rescue NotFoundError => e
      swallow_only_if_gone(message_id, "mark_read", e)
    end

    # Best-effort tidy-up after +mark_read+, so a failure here cannot cause reprocessing.
    def move(message_id, folder)
      return nil unless outbound?

      # Resolve the folder OUTSIDE the rescue below: its own GET/POST against /mailFolders would
      # otherwise turn a folder 404 into "message gone" and swallow a setup problem.
      destination = folder_id(folder)

      begin
        graph_request(:post, "/users/#{@mailbox}/messages/#{message_id}/move",
                body: { destinationId: destination })
        nil
      rescue NotFoundError => e
        swallow_only_if_gone(message_id, "move", e)
      end
    end

    # For the reject paths (no expense exists, so a failure just retries). Moves BEFORE marking
    # read: a move failure leaves the message unread and retried, whereas read-then-fail strands
    # it in the Inbox, never fetched again. The reverse edge (moved, mark_read fails) leaves an
    # unread message in Rejected/Processed, which is less bad than reprocessing. A 404 propagates
    # unless the message is confirmed gone, so a moved-but-present message aborts into
    # MailboxPollJob#process's rescue: logged, reported, left unread.
    def mark_read_and_move(message_id, folder)
      move(message_id, folder)
      mark_read(message_id)
      nil
    end

    private

    # A reply/mark_read/move 404'd. Usually someone handled the message by hand in Outlook after
    # the poll listed it, which is not worth alerting on every cycle: swallowed, but only once
    # CONFIRMED. A 404 alone does not prove it is gone: Exchange changes a message's id on move,
    # so it can mean "still here, still unread, under a new id". Swallowing that would hide a
    # failed mutation, which MailboxPollJob detects only by the raise.
    def swallow_only_if_gone(message_id, action, error)
      raise error if message_present?(message_id)

      Rails.logger.info(
        "Graph mailbox #{@mailbox}: message #{message_id} confirmed gone (404) on #{action}; nothing to do"
      )
      nil
    end

    # Read-only probe on the same id. Only a 404 proves the message is gone; anything
    # inconclusive (5xx, timeout, auth) fails CLOSED as "present" and takes the loud path.
    def message_present?(message_id)
      graph_request(:get, "/users/#{@mailbox}/messages/#{message_id}", params: { "$select" => "id" })
      true
    rescue NotFoundError
      false
    rescue StandardError
      true
    end

    # Belt and braces against mutations in non-production without an opt-in, e.g. from a dev
    # console outside the poll job. Deliberately NOT enforced in GraphAuth#graph_request:
    # find_or_create_folder's POST would return {} and blow up .fetch("id").
    def outbound?
      @settings.outbound_enabled?
    end

    # Folder ids never change, so they are cached across job runs.
    def folder_id(key)
      @folder_ids[key] ||= Rails.cache.fetch("reimbursements/graph-folder/#{@mailbox}/#{key}",
                                             expires_in: 12.hours) do
        find_or_create_folder(FOLDERS.fetch(key))
      end
    end

    def find_or_create_folder(name)
      response = graph_request(:get, "/users/#{@mailbox}/mailFolders",
                         params: { "$filter" => "displayName eq '#{name}'" })
      existing = response.fetch("value").first
      return existing.fetch("id") if existing

      graph_request(:post, "/users/#{@mailbox}/mailFolders", body: { displayName: name }).fetch("id")
    end
  end
end
