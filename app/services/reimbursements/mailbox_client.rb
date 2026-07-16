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
      graph_request(:post, "/users/#{@mailbox}/messages/#{message_id}/reply",
              body: { comment: html })
      nil
    end

    # The idempotency commit point: unread_messages filters on isRead eq false,
    # so once a message is read the next poll won't re-fetch (and re-process)
    # it. Kept separate from +move+ so a move failure never leaves it unread.
    def mark_read(message_id)
      graph_request(:patch, "/users/#{@mailbox}/messages/#{message_id}", body: { isRead: true })
      nil
    end

    # Files the message under Processed/Rejected. Best-effort tidy-up: it runs
    # after +mark_read+, so a failure here can't cause reprocessing.
    def move(message_id, folder)
      graph_request(:post, "/users/#{@mailbox}/messages/#{message_id}/move",
              body: { destinationId: folder_id(folder) })
      nil
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
    def mark_read_and_move(message_id, folder)
      move(message_id, folder)
      mark_read(message_id)
      nil
    end

    private

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
