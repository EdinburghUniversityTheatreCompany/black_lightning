module Reimbursements
  ##
  # Microsoft Graph client for the shared reimbursements mailbox, using
  # app-only (client-credentials) auth — the Entra app is scoped to just this
  # mailbox via an ApplicationAccessPolicy. Send and receive go through the
  # same credential, which is why we poll instead of ActionMailbox.
  class MailboxClient
    include GraphAuth

    FOLDERS = { processed: "Processed", rejected: "Rejected" }.freeze
    PAGE_SIZE = 20

    # The app-only auth + request plumbing (token, request, error surfacing) now
    # lives in GraphAuth, shared with GraphClient. Keep the historical error
    # constant names pointing at the shared classes so existing rescues hold.
    Error = GraphAuth::Error
    AuthError = GraphAuth::AuthError
    NotFoundError = GraphAuth::NotFoundError

    Message = Struct.new(:id, :from_address, :subject, :body_text, keyword_init: true)

    def initialize(mailbox: CostCentre.default&.receive_mailbox, settings: Settings, http: nil, clock: nil)
      @mailbox = mailbox
      @settings = settings
      @http = http || HttpTransport
      @clock = clock || -> { Time.current }
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

    # Every file attachment counts, including images pasted into the body
    # (inline) — signature logos are rare enough that reviewers just ignore
    # them. Only attached mail items (forwarded messages) are skipped.
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

    # The idempotency commit point: unread_messages filters on isRead eq false,
    # so once a message is read the next poll won't re-fetch (and re-process)
    # it. Kept separate from +move+ so a move failure never leaves it unread.
    def mark_read(message_id)
      return nil unless outbound?

      graph_request(:patch, "/users/#{@mailbox}/messages/#{message_id}", body: { isRead: true })
      nil
    rescue NotFoundError => e
      swallow_only_if_gone(message_id, "mark_read", e)
    end

    # Files the message under Processed/Rejected. Best-effort tidy-up: it runs
    # after +mark_read+, so a failure here can't cause reprocessing.
    def move(message_id, folder)
      return nil unless outbound?

      # Resolve the destination folder OUTSIDE the rescue below. folder_id ->
      # find_or_create_folder issues its own GET (and possibly POST) against
      # /mailFolders, so folding it into the message-scoped rescue mislabelled a
      # 404 from a folder misconfiguration as "the message is gone" and swallowed
      # it — hiding a real setup problem completely.
      destination = folder_id(folder)

      begin
        graph_request(:post, "/users/#{@mailbox}/messages/#{message_id}/move",
                body: { destinationId: destination })
        nil
      rescue NotFoundError => e
        swallow_only_if_gone(message_id, "move", e)
      end
    end

    # Convenience for the reject paths (no expense created, so a failure just
    # retries next cycle). Moves first, then marks read — a move failure
    # leaves the message unread (retried next cycle, genuinely safe here: no
    # expense exists yet), rather than the reverse order, which would leave a
    # read-but-unfiled message silently stuck in the Inbox forever
    # (unread_messages would never fetch it again to retry the move). This
    # ordering has a narrower, symmetric edge case of its own: if the move
    # succeeds but the follow-up mark_read call fails, the message is now
    # unread but sitting in Rejected/Processed, invisible to both the normal
    # Inbox retry path and anyone watching that folder for unread mail.
    # Accepted trade-off — the failure it fixes (reprocessing risk) is worse
    # than the one it leaves (a single stray unread message in a folder), and
    # both require a Graph call to fail in the narrow gap between two
    # adjacent requests.
    #
    # A 404 on either call now propagates unless the message is confirmed gone
    # (see swallow_only_if_gone), so a moved-but-present message aborts this pair
    # into MailboxPollJob#process's rescue: logged, reported, and left unread for
    # the next cycle. That is the right outcome here — no expense exists yet, and
    # the message genuinely has not been filed.
    def mark_read_and_move(message_id, folder)
      move(message_id, folder)
      mark_read(message_id)
      nil
    end

    private

    # A message-scoped mutation (reply / mark_read / move) 404'd. That is USUALLY
    # because someone handled or deleted the message by hand in Outlook between the
    # poll's listing and this call: nothing left to reply to, mark read or file, and
    # alerting on it every retry cycle would be pure noise. So the 404 is swallowed
    # — but only once we have CONFIRMED it.
    #
    # A 404 alone does not prove the message is gone: Exchange CHANGES a message's
    # id when the message is moved, so the same 404 can mean "still in the mailbox,
    # still unread, just under a new id". Swallowing that case defeated the whole
    # loud path this client's callers depend on — MailboxPollJob detects a mark_read
    # failure only by the raise, so a moved-but-present message meant the draft was
    # created, mark_read reported success, the reply 404'd so the sender was never
    # told, the move 404'd, and nothing above logger.info fired: no Honeybadger, no
    # duplicate_risk flag, the email silently abandoned.
    def swallow_only_if_gone(message_id, action, error)
      raise error if message_present?(message_id)

      Rails.logger.info(
        "Reimbursements mailbox: message #{message_id} confirmed gone (404) on #{action}; nothing to do"
      )
      nil
    end

    # Read-only existence probe on the same message id the mutation used. Only a
    # 404 here proves the message is really gone. Anything else inconclusive (a
    # 5xx, a timeout, an auth problem) fails CLOSED as "still present", so an
    # unclear answer takes the loud path rather than quietly abandoning a message
    # that may still need processing.
    def message_present?(message_id)
      graph_request(:get, "/users/#{@mailbox}/messages/#{message_id}", params: { "$select" => "id" })
      true
    rescue NotFoundError
      false
    rescue StandardError
      true
    end

    # Belt-and-braces guard against outbound mutations (reply / move / mark_read)
    # in non-production without an explicit opt-in — even if someone drives a
    # MailboxClient from a dev `rails console` outside the poll job (whose own
    # guard already covers the recurring path). Reads/probes stay ungated. NB:
    # deliberately NOT enforced inside GraphAuth#graph_request — find_or_create_folder
    # does a GET then a POST, and a blanket verb-level block would make the POST
    # return {} and blow up .fetch("id").
    def outbound?
      @settings.outbound_enabled?
    end

    # Folder ids never change once created, so they're cached across job runs
    # (a fresh client per run would otherwise re-query Graph each cycle).
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
