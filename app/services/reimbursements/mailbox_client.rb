module Reimbursements
  ##
  # Microsoft Graph client for the shared reimbursements mailbox, using
  # app-only (client-credentials) auth — the Entra app is scoped to just this
  # mailbox via an ApplicationAccessPolicy. Send and receive go through the
  # same credential, which is why we poll instead of ActionMailbox.
  class MailboxClient
    GRAPH_URL = "https://graph.microsoft.com/v1.0".freeze
    TOKEN_URL = "https://login.microsoftonline.com".freeze
    FOLDERS = { processed: "Processed", rejected: "Rejected" }.freeze
    PAGE_SIZE = 20

    class Error < StandardError; end

    # Credential problems (expired/revoked client secret) — surfaced to the
    # IT subcommittee by the poll job rather than retried blindly.
    class AuthError < Error; end

    Message = Struct.new(:id, :from_address, :subject, :body_text, :has_attachments,
                         keyword_init: true)

    def initialize(mailbox: CostCentre.default.mailbox, settings: Settings, http: nil, clock: nil)
      @mailbox = mailbox
      @settings = settings
      @http = http || HttpTransport
      @clock = clock || -> { Time.current }
      @folder_ids = {}
    end

    def unread_messages
      response = request(:get, "/users/#{@mailbox}/mailFolders/inbox/messages",
                         params: { "$filter" => "isRead eq false",
                                   "$select" => "id,subject,from,bodyPreview,hasAttachments",
                                   "$top" => PAGE_SIZE })
      response.fetch("value").map do |raw|
        Message.new(
          id: raw["id"],
          from_address: raw.dig("from", "emailAddress", "address").to_s.downcase,
          subject: raw["subject"].to_s,
          body_text: raw["bodyPreview"].to_s,
          has_attachments: raw["hasAttachments"].present?
        )
      end
    end

    # Every file attachment counts, including images pasted into the body
    # (inline) — signature logos are rare enough that reviewers just ignore
    # them. Only attached mail items (forwarded messages) are skipped.
    def attachments(message_id)
      response = request(:get, "/users/#{@mailbox}/messages/#{message_id}/attachments")
      response.fetch("value").filter_map do |attachment|
        next unless attachment["@odata.type"] == "#microsoft.graph.fileAttachment"
        next if attachment["contentBytes"].blank?

        { filename: attachment["name"].to_s,
          content_type: attachment["contentType"].to_s,
          bytes: Base64.decode64(attachment["contentBytes"]) }
      end
    end

    def reply(message_id, html:)
      request(:post, "/users/#{@mailbox}/messages/#{message_id}/reply",
              body: { comment: html })
      nil
    end

    # The commit point for a processed message: replies happen before this,
    # so a crash in between re-processes (never silently drops) the email.
    def mark_read_and_move(message_id, folder)
      request(:patch, "/users/#{@mailbox}/messages/#{message_id}", body: { isRead: true })
      request(:post, "/users/#{@mailbox}/messages/#{message_id}/move",
              body: { destinationId: folder_id(folder) })
      nil
    end

    private

    def folder_id(key)
      @folder_ids[key] ||= find_or_create_folder(FOLDERS.fetch(key))
    end

    def find_or_create_folder(name)
      response = request(:get, "/users/#{@mailbox}/mailFolders",
                         params: { "$filter" => "displayName eq '#{name}'" })
      existing = response.fetch("value").first
      return existing.fetch("id") if existing

      request(:post, "/users/#{@mailbox}/mailFolders", body: { displayName: name }).fetch("id")
    end

    def request(http_method, path, params: nil, body: nil)
      uri = URI("#{GRAPH_URL}#{path}")
      uri.query = URI.encode_www_form(params) if params
      headers = { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
      status, response_body = @http.call(http_method, uri, headers, body&.to_json)

      raise AuthError, "Graph rejected the token (#{status})" if [ 401, 403 ].include?(status)
      unless (200..299).cover?(status)
        raise Error, "Graph #{http_method.to_s.upcase} #{path} failed (#{status}): " \
                     "#{response_body.to_s.truncate(200)}"
      end

      response_body.blank? ? {} : JSON.parse(response_body)
    end

    def token
      return @token if @token && @token_expires_at.after?(@clock.call + 60)

      fetch_token
    end

    def fetch_token
      uri = URI("#{TOKEN_URL}/#{@settings.azure_tenant_id}/oauth2/v2.0/token")
      form = URI.encode_www_form(
        client_id: @settings.azure_client_id,
        client_secret: @settings.azure_client_secret,
        scope: "https://graph.microsoft.com/.default",
        grant_type: "client_credentials"
      )
      status, response_body = @http.call(:post, uri,
                                         { "Content-Type" => "application/x-www-form-urlencoded" }, form)

      unless status == 200
        message = "Graph token request failed (#{status}): #{response_body.to_s.truncate(300)}"
        raise AuthError, message if [ 400, 401 ].include?(status)

        raise Error, message
      end

      data = JSON.parse(response_body)
      @token_expires_at = @clock.call + data.fetch("expires_in", 3600).to_i
      @token = data.fetch("access_token")
    end
  end
end
