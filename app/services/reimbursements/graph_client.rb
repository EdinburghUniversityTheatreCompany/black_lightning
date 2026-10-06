module Reimbursements
  # Graph client for the operator side: the EUSA draft and notification emails, SharePoint
  # uploads (receipts, BACS xlsx) and the folder picker. App-only auth, shared with
  # Graph::MailboxClient via GraphAuth.
  #
  # Permissions (manual setup, docs/graph-mailbox-rbac.md) come from two systems:
  #   * Mail is NOT an Entra grant: Exchange assigns "Application Mail Full Access" over a
  #     management scope naming each mailbox. Consenting Mail.* in Entra would re-grant the
  #     whole tenant, since the two systems union rather than intersect.
  #   * Sites.Selected is an Entra permission granted per site. It cannot search sites, so the
  #     Settings picker addresses each cost centre's configured site by URL (#get_site).
  class GraphClient
    include ::GraphAuth

    # Graph's cap for inline draft attachments; larger ones need an upload session.
    INLINE_ATTACHMENT_LIMIT = 3_000_000
    SIMPLE_UPLOAD_LIMIT = 4 * 1024 * 1024
    UPLOAD_CHUNK_SIZE = 4 * 1024 * 1024

    # An outgoing email attachment (the BACS xlsx or a renamed receipt).
    Attachment = Struct.new(:filename, :content, :content_type, keyword_init: true)

    Site = Struct.new(:id, :name, :web_url, keyword_init: true)
    Drive = Struct.new(:id, :name, keyword_init: true)
    Item = Struct.new(:id, :name, :folder, :web_url, keyword_init: true)

    # +id+ is stored on the Batch so a reopen can delete the stale draft; +web_link+ opens it in Outlook.
    Draft = Struct.new(:id, :web_link, keyword_init: true)

    def initialize(settings: Settings, http: nil, clock: nil, sleeper: nil)
      @settings = settings
      @http = http || ::HttpTransport
      @clock = clock || -> { Time.current }
      @sleeper = sleeper
    end

    # Small attachments are inlined; large ones stream via an upload session once the draft exists.
    def create_draft(mailbox:, to:, subject:, html:, attachments: [], cc: [])
      unless @settings.outbound_enabled?
        Rails.logger.info("Reimbursements create_draft suppressed (outbound disabled): to=#{Array(to).join(',')}")
        return Draft.new(id: "suppressed-#{SecureRandom.hex(4)}", web_link: "")
      end
      inline, large = Array(attachments).partition { |a| a.content.to_s.bytesize < INLINE_ATTACHMENT_LIMIT }

      payload = {
        subject: subject,
        body: { contentType: "HTML", content: html },
        toRecipients: recipients(to),
        ccRecipients: recipients(cc)
      }
      payload[:attachments] = inline.map { |a| inline_attachment(a) } if inline.any?

      draft = graph_request(:post, "/users/#{mailbox}/messages", body: payload)
      message_id = draft.fetch("id")
      large.each { |a| upload_large_attachment(mailbox, message_id, a) }
      Draft.new(id: message_id, web_link: draft["webLink"].to_s)
    end

    # Gated, and RAISES when suppressed rather than returning nil (its success value): a silent
    # no-op would have BatchesController report the old EUSA draft deleted while it sits in
    # Outlook, ready to send beside the rebuilt one.
    def delete_message(mailbox:, message_id:)
      refuse_outbound!("delete message #{message_id} from #{mailbox}")
      graph_request(:delete, "/users/#{mailbox}/messages/#{message_id}")
      nil
    end

    # Required before a reopen deletes a draft, so one already sent by hand in Outlook is never
    # mistaken for discardable. Any failure to confirm (404, permissions, outage) means not confirmed.
    def draft_message?(mailbox:, message_id:)
      message = graph_request(:get, "/users/#{mailbox}/messages/#{message_id}", params: { "$select" => "isDraft" })
      message["isDraft"] == true
    rescue StandardError
      # Not just GraphAuth::Error: a raw transport error (timeout, DNS, TLS) never reaches the
      # status check and must fail closed too.
      false
    end

    # Sends immediately, no attachments. Notifier uses this for the rejection, producer and
    # operator emails.
    def send_mail(mailbox:, to:, subject:, html:)
      unless @settings.outbound_enabled?
        Rails.logger.info("Reimbursements send_mail suppressed (outbound disabled): to=#{Array(to).join(',')} subject=#{subject.inspect}")
        return nil
      end
      graph_request(:post, "/users/#{mailbox}/sendMail",
                    body: { message: { subject: subject,
                                       body: { contentType: "HTML", content: html },
                                       toRecipients: recipients(to) },
                            saveToSentItems: true })
      nil
    end

    # Returns the webUrl. Gated, and RAISES when suppressed: this carries the bank details (BACS
    # xlsx, receipts), and BatchProcessor stamps receipts_offloaded from a returned URL, which
    # tells an operator it is safe to delete the only local copy.
    def upload_to_folder(drive_id:, folder_id:, filename:, content:)
      refuse_outbound!("SharePoint upload of #{filename}")
      raise ::GraphAuth::Error, "cannot upload empty file: #{filename}" if content.to_s.empty?

      # Percent-encode only the filename segment (spaces and parens break URI()); the :/…:/content
      # delimiters in the format strings below must stay literal.
      safe_name = ERB::Util.url_encode(filename.to_s.tr("/\\", "__"))
      if content.bytesize < SIMPLE_UPLOAD_LIMIT
        url = "#{GraphAuth::GRAPH_URL}/drives/#{drive_id}/items/#{folder_id}:/#{safe_name}:/content"
        graph_raw_request(:put, url, content, content_type: "application/octet-stream")["webUrl"].to_s
      else
        session_url = "#{GraphAuth::GRAPH_URL}/drives/#{drive_id}/items/#{folder_id}:/#{safe_name}:/createUploadSession"
        upload_url = graph_request(:post, session_url, body: {}).fetch("uploadUrl")
        upload_in_chunks(upload_url, content)["webUrl"].to_s
      end
    end

    # Read probe that the app can reach a mailbox, i.e. the address matches the Exchange scope
    # behind its mail access (one scope gates read, send and poll). Raises on 403 etc. Exchange
    # caches the scope for up to 2 hours, so a mailbox added moments ago still fails here.
    def check_mailbox(address)
      graph_request(:get, "/users/#{address}/mailFolders/inbox", params: { "$select" => "id" })
      true
    end

    # Acquires an app-only token: confirms the Azure credentials work and Microsoft login is
    # reachable, touching no mailbox or site. Raises on failure.
    def check_reachable
      graph_token
      true
    end

    # --- SharePoint browse (Settings folder picker) ------------------------

    # Resolves a site by its browser URL through the server-relative path form. A Sites.Selected
    # app can address a granted site by path but cannot search the tenant.
    def get_site(site_url)
      uri = URI(site_url.to_s.strip)
      site = graph_request(:get, "/sites/#{uri.host}:#{uri.path.to_s.chomp('/')}")
      Site.new(id: site["id"], name: site["displayName"].presence || site["name"].to_s,
               web_url: site["webUrl"].to_s)
    end

    def list_drives(site_id)
      paginated(:get, "/sites/#{site_id}/drives").map do |drive|
        Drive.new(id: drive["id"], name: drive["name"].presence || "Documents")
      end
    end

    def list_folder_contents(drive_id:, item_id: nil)
      path = item_id ? "/drives/#{drive_id}/items/#{item_id}/children" : "/drives/#{drive_id}/root/children"
      paginated(:get, path).map do |item|
        Item.new(id: item["id"], name: item["name"].to_s, folder: item.key?("folder"),
                 web_url: item["webUrl"].to_s)
      end
    end

    private

    # Gate for calls with a side effect (everything except reads), not just mail: the credentials
    # that read a tenant can also write to it, and SharePoint upload and message delete carry bank
    # details. Production always passes; elsewhere needs REIMBURSEMENTS_ENABLE_OUTBOUND.
    # create_draft and send_mail stub instead (a "suppressed-" id, nil) so a dev Build Batch still
    # walks the flow; only calls whose stub could pass for success raise.
    def refuse_outbound!(description)
      return if @settings.outbound_enabled?

      raise ::GraphAuth::OutboundSuppressedError,
            "Reimbursements refused an outbound Graph side effect in #{Rails.env}: #{description}. " \
            "Set REIMBURSEMENTS_ENABLE_OUTBOUND to opt in (only against a throwaway tenant)."
    end

    # Follows @odata.nextLink so a long list isn't truncated to its first page.
    def paginated(http_method, path)
      items = []
      next_link = path
      loop do
        page = graph_request(http_method, next_link)
        items.concat(page.fetch("value", []))
        next_link = page["@odata.nextLink"]
        break if next_link.blank?
      end
      items
    end

    # Hand-entered addresses carry stray whitespace, which Graph rejects.
    def recipients(addresses)
      Array(addresses).filter_map do |address|
        cleaned = address.to_s.strip
        { emailAddress: { address: cleaned } } unless cleaned.empty?
      end
    end

    def inline_attachment(attachment)
      { "@odata.type": "#microsoft.graph.fileAttachment",
        name: attachment.filename,
        contentType: attachment.content_type,
        contentBytes: Base64.strict_encode64(attachment.content) }
    end

    def upload_large_attachment(mailbox, message_id, attachment)
      session_url = "/users/#{mailbox}/messages/#{message_id}/attachments/createUploadSession"
      upload_url = graph_request(:post, session_url,
                                 body: { AttachmentItem: { attachmentType: "file",
                                                          name: attachment.filename,
                                                          size: attachment.content.bytesize,
                                                          contentType: attachment.content_type } })
                     .fetch("uploadUrl")
      upload_in_chunks(upload_url, attachment.content)
    end

    # Streams to a pre-authenticated upload session; returns the final chunk's response (the item).
    def upload_in_chunks(upload_url, content)
      total = content.bytesize
      last = {}
      (0...total).step(UPLOAD_CHUNK_SIZE) do |start|
        finish = [ start + UPLOAD_CHUNK_SIZE, total ].min - 1
        chunk = content.byteslice(start..finish)
        headers = { "Content-Length" => chunk.bytesize.to_s,
                    "Content-Range" => "bytes #{start}-#{finish}/#{total}" }
        status, body = @http.call(:put, URI(upload_url), headers, chunk)
        raise ::GraphAuth::Error, "chunk upload failed (#{status})" unless (200..299).cover?(status)

        last = body.blank? ? last : JSON.parse(body)
      end
      last
    end
  end
end
