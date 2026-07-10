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
  #   * Mail.Send            — send the EUSA draft / producer notifications
  #   * Mail.ReadWrite       — create the EUSA draft in the send mailbox
  #   * Files.ReadWrite.All  — upload receipts + BACS xlsx to SharePoint
  #   * Sites.ReadWrite.All  — browse sites/drives/folders for the picker
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

    def initialize(settings: Settings, http: nil, clock: nil)
      @settings = settings
      @http = http || HttpTransport
      @clock = clock || -> { Time.current }
    end

    # Create a draft in the shared mailbox and return its webLink (open in
    # Outlook on the web to review, then send manually). Small attachments are
    # inlined; large ones stream via an upload session after the draft exists.
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
      draft["webLink"].to_s
    end

    # Send an email immediately (producer notifications go via ActionMailer, but
    # this is here for the "you've been paid" / nightly paths). No attachments.
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

    # --- SharePoint browse (Settings folder picker, Phase F) ---------------

    def list_sites(search: "*")
      graph_request(:get, "/sites", params: { search: search }).fetch("value", []).map do |site|
        Site.new(id: site["id"], name: site["displayName"].presence || site["name"].to_s,
                 web_url: site["webUrl"].to_s)
      end
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
