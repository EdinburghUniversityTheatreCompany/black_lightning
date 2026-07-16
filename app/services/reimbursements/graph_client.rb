module Reimbursements
  ##
  # Microsoft Graph client for the *operator* side of reimbursements: creating
  # and sending the EUSA email, uploading receipts + the BACS xlsx to
  # SharePoint, and browsing SharePoint for the Settings folder picker (Phase F).
  # Ports bedlam-bacs graph_client.py, swapping its per-user interactive OAuth
  # (a desktop, single-user assumption) for the same app-only client-credentials
  # auth the shipped MailboxClient uses — a multi-user web app can't do
  # interactive OAuth. Auth + request plumbing is shared via GraphAuth.
  #
  # Azure app-registration permissions required (application permissions, admin
  # consent — a MANUAL setup step, see the reimbursements setup guide):
  #   * Mail.Send       — send the EUSA draft / producer notifications
  #   * Mail.ReadWrite  — create the EUSA draft in the send mailbox
  #   * Sites.Selected  — SharePoint, granted write per-site (least-privilege):
  #                       upload receipts + BACS xlsx and browse a granted site's
  #                       drives/folders. Cannot search/enumerate sites, so the
  #                       Settings picker addresses each cost centre's configured
  #                       site by URL (see #get_site).
  class GraphClient
    include GraphAuth

    # Attachments under this size are inlined into the draft's create payload;
    # larger ones need a per-attachment upload session (Graph's documented cap).
    INLINE_ATTACHMENT_LIMIT = 3_000_000
    # Files under this size use the simple upload endpoint; larger ones a session.
    SIMPLE_UPLOAD_LIMIT = 4 * 1024 * 1024
    UPLOAD_CHUNK_SIZE = 4 * 1024 * 1024

    # An outgoing email attachment (the BACS xlsx or a renamed receipt).
    Attachment = Struct.new(:filename, :content, :content_type, keyword_init: true) do
      def initialize(filename:, content:, content_type: "application/octet-stream")
        super
      end
    end

    Site = Struct.new(:id, :name, :web_url, keyword_init: true)
    Drive = Struct.new(:id, :name, keyword_init: true)
    Item = Struct.new(:id, :name, :folder, :web_url, keyword_init: true)

    # A created draft: its message +id+ (stored on the Batch so a reopen can
    # delete the stale draft) and its +web_link+ (opened in Outlook to review + send).
    Draft = Struct.new(:id, :web_link, keyword_init: true)

    def initialize(settings: Settings, http: nil, clock: nil)
      @settings = settings
      @http = http || HttpTransport
      @clock = clock || -> { Time.current }
    end

    # Create a draft in the shared mailbox and return a Draft (its message id +
    # webLink — open in Outlook on the web to review, then send manually). Small
    # attachments are inlined; large ones stream via an upload session after the
    # draft exists.
    def create_draft(mailbox:, to:, subject:, html:, attachments: [], cc: [])
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

    # Delete a message from a mailbox — used to clean up the stale EUSA draft
    # when a batch is reopened for rebuild. Graph replies 204 (no body).
    def delete_message(mailbox:, message_id:)
      graph_request(:delete, "/users/#{mailbox}/messages/#{message_id}")
      nil
    end

    # Verifies a message still exists as an unsent draft — required before a
    # reopen deletes it, so a batch whose draft was already sent by hand in
    # Outlook (this app has no visibility into that step by design) is never
    # mistaken for one still safe to discard. Any failure to confirm — the
    # message was deleted/sent/moved (a 404), a permissions issue, or a
    # genuine Graph outage — is treated identically as NOT confirmed, so the
    # caller refuses to reopen rather than assuming the safe case.
    def draft_message?(mailbox:, message_id:)
      message = graph_request(:get, "/users/#{mailbox}/messages/#{message_id}", params: { "$select" => "isDraft" })
      message["isDraft"] == true
    rescue StandardError
      # Not just GraphAuth::Error: a genuine network-level outage (timeout,
      # DNS failure, TLS error) raises a raw transport exception that never
      # reaches graph_request's own status check, and must fail closed here
      # exactly like a 404/permissions error would.
      false
    end

    # Send an email immediately from the mailbox (Notifier uses this for the
    # rejection / "you've been paid" / producer / operator emails). No attachments.
    def send_mail(mailbox:, to:, subject:, html:)
      graph_request(:post, "/users/#{mailbox}/sendMail",
                    body: { message: { subject: subject,
                                       body: { contentType: "HTML", content: html },
                                       toRecipients: recipients(to) },
                            saveToSentItems: true })
      nil
    end

    # Upload a file into a SharePoint folder; returns its webUrl.
    def upload_to_folder(drive_id:, folder_id:, filename:, content:)
      raise GraphAuth::Error, "cannot upload empty file: #{filename}" if content.to_s.empty?

      safe_name = filename.to_s.tr("/\\", "__")
      if content.bytesize < SIMPLE_UPLOAD_LIMIT
        url = "#{GraphAuth::GRAPH_URL}/drives/#{drive_id}/items/#{folder_id}:/#{safe_name}:/content"
        graph_raw_request(:put, url, content, content_type: "application/octet-stream")["webUrl"].to_s
      else
        session_url = "#{GraphAuth::GRAPH_URL}/drives/#{drive_id}/items/#{folder_id}:/#{safe_name}:/createUploadSession"
        upload_url = graph_request(:post, session_url, body: {}).fetch("uploadUrl")
        upload_in_chunks(upload_url, content)["webUrl"].to_s
      end
    end

    # Download bytes from a (signed, pre-authenticated) URL — receipts from
    # Airtable, whose URLs expire after ~2h, so always fetch fresh in one run.
    # No Graph auth header: the URL carries its own token.
    def download(url)
      status, body = @http.call(:get, URI(url), {}, nil)
      raise GraphAuth::Error, "receipt download failed (#{status})" unless (200..299).cover?(status)

      body
    end

    # A light read probe confirming the app can reach a mailbox, i.e. it sits in
    # the Exchange ApplicationAccessPolicy group that scopes Mail.* for this app.
    # Returns true on success; raises (403 etc.) so the Settings access-check turns
    # it into a failed row with the Graph message. Same group gates send + poll, so
    # this read is a fair proxy for "email-in and batch drafting will work".
    def check_mailbox(address)
      graph_request(:get, "/users/#{address}/mailFolders/inbox", params: { "$select" => "id" })
      true
    end

    # A minimal reachability probe for the integration status dashboard: acquire
    # an app-only Graph token. Confirms the Azure app credentials are valid and
    # login.microsoftonline.com is reachable, without touching any mailbox or
    # site (that per-resource access is the Settings access-check's job). Returns
    # true; raises (AuthError/Error) so the dashboard turns a failure into a
    # failed row carrying the message.
    def check_reachable
      graph_token
      true
    end

    # --- SharePoint browse (Settings folder picker, Phase F) ---------------

    # Resolve a SharePoint site by its browser URL (e.g.
    # "https://tenant.sharepoint.com/sites/Finance") to its Graph Site + id, using
    # the server-relative path form Graph accepts for Sites.Selected apps. Such an
    # app can address a site it's been granted by path but can't search across the
    # tenant, so the Settings picker starts from each cost centre's configured URL.
    def get_site(site_url)
      uri = URI(site_url.to_s.strip)
      site = graph_request(:get, "/sites/#{uri.host}:#{uri.path.to_s.chomp('/')}")
      Site.new(id: site["id"], name: site["displayName"].presence || site["name"].to_s,
               web_url: site["webUrl"].to_s)
    end

    def list_drives(site_id)
      graph_request(:get, "/sites/#{site_id}/drives").fetch("value", []).map do |drive|
        Drive.new(id: drive["id"], name: drive["name"].presence || "Documents")
      end
    end

    def list_folder_contents(drive_id:, item_id: nil)
      path = item_id ? "/drives/#{drive_id}/items/#{item_id}/children" : "/drives/#{drive_id}/root/children"
      graph_request(:get, path).fetch("value", []).map do |item|
        Item.new(id: item["id"], name: item["name"].to_s, folder: item.key?("folder"),
                 web_url: item["webUrl"].to_s)
      end
    end

    private

    # Airtable's free-text email fields carry stray whitespace; an un-stripped
    # address is rejected by Graph as an invalid recipient. Ported from
    # bedlam-bacs _clean_recipients.
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

    # Stream content to a pre-authenticated upload session in 4 MB chunks. The
    # final chunk's response carries the created item (webUrl); return it.
    def upload_in_chunks(upload_url, content)
      total = content.bytesize
      last = {}
      (0...total).step(UPLOAD_CHUNK_SIZE) do |start|
        finish = [ start + UPLOAD_CHUNK_SIZE, total ].min - 1
        chunk = content.byteslice(start..finish)
        headers = { "Content-Length" => chunk.bytesize.to_s,
                    "Content-Range" => "bytes #{start}-#{finish}/#{total}" }
        status, body = @http.call(:put, URI(upload_url), headers, chunk)
        raise GraphAuth::Error, "chunk upload failed (#{status})" unless (200..299).cover?(status)

        last = body.blank? ? last : JSON.parse(body)
      end
      last
    end
  end
end
