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

    # The commit point for a processed message: replies happen before this,
    # so a crash in between re-processes (never silently drops) the email.
    def mark_read_and_move(message_id, folder)
      graph_request(:patch, "/users/#{@mailbox}/messages/#{message_id}", body: { isRead: true })
      graph_request(:post, "/users/#{@mailbox}/messages/#{message_id}/move",
              body: { destinationId: folder_id(folder) })
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
