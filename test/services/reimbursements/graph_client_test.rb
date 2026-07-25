require "test_helper"

module Reimbursements
  class GraphClientTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # Delegates outbound_enabled? to the real Settings so the send/draft
    # suppression guard reads the same REIMBURSEMENTS_ENABLE_OUTBOUND seam the
    # suite sets (test_helper opts in; a suppression test deletes it).
    FakeSettings = Struct.new(:azure_tenant_id, :azure_client_id, :azure_client_secret) do
      def outbound_enabled?
        Reimbursements::Settings.outbound_enabled?
      end
    end

    def settings
      FakeSettings.new("tenant-1", "client-1", "secret-1")
    end

    def token_response
      [ 200, { access_token: "tok-1", expires_in: 3600 }.to_json ]
    end

    def build_client(responses)
      http = FakeHttp.new(responses)
      [ GraphClient.new(settings: settings, http: http, clock: -> { Time.zone.local(2026, 7, 9, 12) }), http ]
    end

    def attachment(bytes, name: "file.pdf")
      GraphClient::Attachment.new(filename: name, content: bytes, content_type: "application/pdf")
    end

    test "create_draft inlines small attachments and returns the draft id + webLink" do
      client, http = build_client([
        token_response,
        [ 201, { id: "msg-1", webLink: "https://outlook.example/msg-1" }.to_json ]
      ])

      draft = client.create_draft(mailbox: "send@bedlamfringe.co.uk",
                                  to: [ "  finance@eusa.ed.ac.uk ", "" ],
                                  subject: "BACS", html: "<p>hi</p>",
                                  attachments: [ attachment("PDFBYTES", name: "bacs.xlsx") ])

      assert_equal "msg-1", draft.id
      assert_equal "https://outlook.example/msg-1", draft.web_link
      post = http.requests.last
      assert_includes post.uri, "/users/send@bedlamfringe.co.uk/messages"
      body = JSON.parse(post.body)
      assert_equal [ "finance@eusa.ed.ac.uk" ], body["toRecipients"].map { |r| r.dig("emailAddress", "address") },
                   "recipient whitespace is stripped and blanks dropped"
      assert_equal Base64.strict_encode64("PDFBYTES"), body["attachments"].sole["contentBytes"]
      assert_equal "bacs.xlsx", body["attachments"].sole["name"]
    end

    test "create_draft streams a >3MB attachment via an upload session" do
      big = "x" * (GraphClient::INLINE_ATTACHMENT_LIMIT + 10)
      client, http = build_client([
        token_response,
        [ 201, { id: "msg-2", webLink: "https://outlook.example/msg-2" }.to_json ], # create draft
        [ 200, { uploadUrl: "https://upload.example/session" }.to_json ],           # createUploadSession
        [ 201, { id: "att-1" }.to_json ]                                            # single chunk PUT
      ])

      client.create_draft(mailbox: "send@x", to: [ "a@x" ], subject: "s", html: "<p>b</p>",
                          attachments: [ attachment(big) ])

      assert(http.requests.any? { |r| r.uri.include?("createUploadSession") })
      chunk = http.requests.last
      assert_equal "put", chunk.method.to_s
      assert_includes chunk.uri, "upload.example/session"
      assert_nil chunk.headers["Authorization"], "chunk PUT uses the pre-authenticated session url"
    end

    test "delete_message issues a DELETE to the mailbox message" do
      client, http = build_client([ token_response, [ 204, "" ] ])

      client.delete_message(mailbox: "send@bedlamfringe.co.uk", message_id: "msg-1")

      del = http.requests.last
      assert_equal "delete", del.method.to_s
      assert_includes del.uri, "/users/send@bedlamfringe.co.uk/messages/msg-1"
    end

    test "draft_message? returns true for a message Graph still reports as an unsent draft" do
      client, http = build_client([ token_response, [ 200, { isDraft: true }.to_json ] ])

      assert client.draft_message?(mailbox: "send@bedlamfringe.co.uk", message_id: "msg-1")
      get = http.requests.last
      assert_equal "get", get.method.to_s
      assert_includes get.uri, "/users/send@bedlamfringe.co.uk/messages/msg-1"
    end

    test "draft_message? returns false when Graph reports the message is no longer a draft" do
      client, = build_client([ token_response, [ 200, { isDraft: false }.to_json ] ])

      assert_not client.draft_message?(mailbox: "send@bedlamfringe.co.uk", message_id: "msg-1")
    end

    test "draft_message? returns false (not confirmed) on a 404 — the message was deleted or moved" do
      client, = build_client([ token_response, [ 404, { error: { message: "not found" } }.to_json ] ])

      assert_not client.draft_message?(mailbox: "send@bedlamfringe.co.uk", message_id: "msg-1")
    end

    test "draft_message? returns false (not confirmed) on a raw transport failure, not just a Graph error" do
      client, = build_client([ token_response, Net::OpenTimeout.new("execution expired") ])

      assert_not client.draft_message?(mailbox: "send@bedlamfringe.co.uk", message_id: "msg-1")
    end

    test "send_mail posts sendMail with saveToSentItems" do
      client, http = build_client([ token_response, [ 202, "" ] ])

      client.send_mail(mailbox: "send@x", to: [ "p@x" ], subject: "Paid", html: "<p>done</p>")

      post = http.requests.last
      assert_includes post.uri, "/users/send@x/sendMail"
      assert JSON.parse(post.body)["saveToSentItems"]
    end

    test "send_mail is suppressed (returns nil, no request) when outbound is disabled" do
      client, http = build_client([ token_response, [ 202, "" ] ])
      original = ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")

      result = client.send_mail(mailbox: "send@x", to: [ "p@x" ], subject: "Paid", html: "<p>done</p>")

      assert_nil result
      assert_empty http.requests, "no Graph call (not even a token) when outbound is disabled"
    ensure
      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = original if original
    end

    test "create_draft is suppressed and returns a stub Draft when outbound is disabled" do
      client, http = build_client([ token_response, [ 201, { id: "msg-1", webLink: "x" }.to_json ] ])
      original = ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")

      draft = client.create_draft(mailbox: "send@x", to: [ "p@x" ], subject: "s", html: "<p>b</p>",
                                  attachments: [ attachment("PDF", name: "bacs.xlsx") ])

      assert_match(/\Asuppressed-/, draft.id)
      assert_equal "", draft.web_link
      assert_empty http.requests, "no Graph call when outbound is disabled"
    ensure
      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = original if original
    end

    # The gate has to be "no outbound Graph SIDE EFFECT", not merely "no outbound
    # mail": upload and delete are the two calls carrying bank details.
    # BatchProcessor uploads the BACS xlsx (full sort codes and account numbers)
    # and every receipt BEFORE create_draft, so an ungated dev shell holding fnox
    # Azure credentials would PUT them into PRODUCTION SharePoint on a Build
    # Batch, and reopen could DELETE a real draft out of the live mailbox.
    #
    # These two raise rather than returning a plausible stub, unlike create_draft /
    # send_mail: a suppressed upload that returned "" or a fake URL would be
    # counted as uploaded by BatchProcessor and stamp receipts_offloaded, telling
    # an operator it is safe to delete the only copy of a receipt that was never
    # backed up; and a suppressed delete that returned nil would tell the operator
    # "the old EUSA draft has been deleted" when it is still sitting there. Both
    # call sites already rescue StandardError into a visible best-effort error, so
    # raising is both louder and truer.
    test "upload_to_folder is suppressed with no Graph request when outbound is disabled" do
      client, http = build_client([ token_response, [ 201, { webUrl: "https://sp.example/r.pdf" }.to_json ] ])
      original = ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")

      error = assert_raises(GraphAuth::OutboundSuppressedError) do
        client.upload_to_folder(drive_id: "drv", folder_id: "fld", filename: "r.pdf", content: "BYTES")
      end

      assert_match(/SharePoint upload/i, error.message)
      assert_empty http.requests, "no Graph call (not even a token) when outbound is disabled"
    ensure
      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = original if original
    end

    test "delete_message is suppressed with no Graph request when outbound is disabled" do
      client, http = build_client([ token_response, [ 204, "" ] ])
      original = ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")

      assert_raises(GraphAuth::OutboundSuppressedError) do
        client.delete_message(mailbox: "send@x", message_id: "msg-1")
      end

      assert_empty http.requests, "no Graph call when outbound is disabled"
    ensure
      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = original if original
    end

    # The whole suite runs with REIMBURSEMENTS_ENABLE_OUTBOUND set, so without
    # this the production branch of the gate is never exercised and deleting
    # `return true if Rails.env.production?` from Settings would stay green while
    # production silently stopped uploading and deleting.
    test "production performs the upload and the delete without the ENV opt-in" do
      original_env = ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")
      original_rails_env = Rails.env
      Rails.env = "production"

      client, http = build_client([
        token_response,
        [ 201, { webUrl: "https://sp.example/r.pdf" }.to_json ],
        [ 204, "" ]
      ])

      assert_equal "https://sp.example/r.pdf",
                   client.upload_to_folder(drive_id: "drv", folder_id: "fld",
                                           filename: "r.pdf", content: "BYTES")
      assert_nil client.delete_message(mailbox: "send@x", message_id: "msg-1")

      methods = http.requests.map { |r| r.method.to_s }
      assert_includes methods, "put", "production must still PUT the file to SharePoint"
      assert_includes methods, "delete", "production must still DELETE the stale draft"
    ensure
      Rails.env = original_rails_env
      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = original_env if original_env
    end

    # Read-only probes must keep working in a dev shell: they are how the Settings
    # dashboard and folder picker report on a real tenant, and they mutate nothing.
    test "read-only Graph probes are not gated by the outbound switch" do
      original = ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")
      client, http = build_client([
        token_response,
        [ 200, { id: "site-1", displayName: "Finance", webUrl: "https://sp.example/sites/f" }.to_json ],
        [ 200, { id: "inbox" }.to_json ],
        [ 200, { isDraft: true }.to_json ]
      ])

      assert_equal "site-1", client.get_site("https://tenant.sharepoint.com/sites/Finance").id
      assert client.check_mailbox("send@x")
      assert client.draft_message?(mailbox: "send@x", message_id: "msg-1")
      graph_calls = http.requests.reject { |r| r.uri.include?("login.microsoftonline.com") }
      assert_equal %w[get get get], graph_calls.map { |r| r.method.to_s },
                   "every probe is a GET; only the token exchange is a POST"
    ensure
      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = original if original
    end

    test "upload_to_folder does a simple PUT for a small file and returns webUrl" do
      client, http = build_client([
        token_response,
        [ 201, { webUrl: "https://sp.example/receipts/r.pdf" }.to_json ]
      ])

      url = client.upload_to_folder(drive_id: "drv", folder_id: "fld", filename: "a/b.pdf", content: "BYTES")

      assert_equal "https://sp.example/receipts/r.pdf", url
      put = http.requests.last
      assert_equal "put", put.method.to_s
      assert_includes put.uri, "/drives/drv/items/fld:/a_b.pdf:/content", "slashes sanitised in filename"
      assert_equal "BYTES", put.body
    end

    test "upload_to_folder percent-encodes spaces and parens in the filename segment" do
      client, http = build_client([
        token_response,
        [ 201, { webUrl: "https://sp.example/receipts/r.pdf" }.to_json ]
      ])

      url = client.upload_to_folder(
        drive_id: "drv", folder_id: "fld",
        filename: "Photoshoot props (2).jpeg", content: "BYTES"
      )

      assert_equal "https://sp.example/receipts/r.pdf", url
      put = http.requests.last
      assert_includes put.uri.to_s,
        "/drives/drv/items/fld:/Photoshoot%20props%20%282%29.jpeg:/content",
        "filename segment percent-encoded, Graph ':/…:/content' delimiters preserved"
    end

    test "upload_to_folder streams a >=4MB file via a chunked upload session" do
      big = "x" * GraphClient::SIMPLE_UPLOAD_LIMIT
      client, http = build_client([
        token_response,
        [ 200, { uploadUrl: "https://upload.example/session" }.to_json ], # createUploadSession
        [ 201, { webUrl: "https://sp.example/receipts/big.pdf" }.to_json ] # chunk PUT
      ])

      url = client.upload_to_folder(drive_id: "drv", folder_id: "fld", filename: "big.pdf", content: big)

      assert_equal "https://sp.example/receipts/big.pdf", url
      assert(http.requests.any? { |r| r.uri.include?("createUploadSession") })
      chunk = http.requests.last
      assert_equal "put", chunk.method.to_s
      assert_includes chunk.uri, "upload.example/session"
      assert_equal big.bytesize, chunk.body.bytesize
    end

    test "upload_to_folder percent-encodes the filename in the chunked createUploadSession URL" do
      big = "x" * GraphClient::SIMPLE_UPLOAD_LIMIT
      client, http = build_client([
        token_response,
        [ 200, { uploadUrl: "https://upload.example/session" }.to_json ], # createUploadSession
        [ 201, { webUrl: "https://sp.example/receipts/big.pdf" }.to_json ] # chunk PUT
      ])

      url = client.upload_to_folder(drive_id: "drv", folder_id: "fld",
                                    filename: "Photoshoot props (2).jpeg", content: big)

      assert_equal "https://sp.example/receipts/big.pdf", url
      session = http.requests.find { |r| r.uri.to_s.include?("createUploadSession") }
      assert_includes session.uri.to_s,
        "/drives/drv/items/fld:/Photoshoot%20props%20%282%29.jpeg:/createUploadSession",
        "filename segment percent-encoded in the >=4MB createUploadSession URL too"
    end

    test "upload_to_folder's small-file PUT raises AuthError on a 401/403 (graph_raw_request)" do
      client, = build_client([ token_response, [ 403, "forbidden" ] ])

      assert_raises(GraphAuth::AuthError) do
        client.upload_to_folder(drive_id: "drv", folder_id: "fld", filename: "a.pdf", content: "BYTES")
      end
    end

    test "upload_to_folder's small-file PUT raises Error on any other non-2xx (graph_raw_request)" do
      client, = build_client([ token_response, [ 500, "boom" ] ])

      assert_raises(GraphAuth::Error) do
        client.upload_to_folder(drive_id: "drv", folder_id: "fld", filename: "a.pdf", content: "BYTES")
      end
    end

    test "upload_to_folder's small-file PUT raises NotFoundError on a 404, still loud (graph_raw_request)" do
      # 404s are only swallowed on the mailbox mutation paths (a vanished
      # message is genuinely nothing to do). A 404 uploading a receipt means a
      # missing drive/folder — a real error that must fail loudly, not vanish.
      client, = build_client([ token_response, [ 404, { error: { code: "itemNotFound" } }.to_json ] ])

      assert_raises(GraphAuth::NotFoundError) do
        client.upload_to_folder(drive_id: "drv", folder_id: "fld", filename: "a.pdf", content: "BYTES")
      end
    end

    test "upload_to_folder refuses an empty file" do
      client, = build_client([ token_response ])
      assert_raises(GraphAuth::Error) do
        client.upload_to_folder(drive_id: "d", folder_id: "f", filename: "x.pdf", content: "")
      end
    end

    test "upload_to_folder's chunked path issues one PUT per chunk for a genuinely multi-chunk file" do
      big = "x" * (GraphClient::UPLOAD_CHUNK_SIZE + 1)
      client, http = build_client([
        token_response,
        [ 200, { uploadUrl: "https://upload.example/session" }.to_json ], # createUploadSession
        [ 202, "" ],                                                     # chunk 1 PUT (not yet complete)
        [ 201, { webUrl: "https://sp.example/receipts/big.pdf" }.to_json ] # chunk 2 PUT (final)
      ])

      url = client.upload_to_folder(drive_id: "drv", folder_id: "fld", filename: "big.pdf", content: big)

      assert_equal "https://sp.example/receipts/big.pdf", url
      chunk_puts = http.requests.select { |r| r.method.to_s == "put" && r.uri.include?("upload.example/session") }
      assert_equal 2, chunk_puts.size, "a file just over one chunk size must issue exactly 2 chunk PUTs"
      assert_equal GraphClient::UPLOAD_CHUNK_SIZE, chunk_puts.first.body.bytesize
      assert_equal 1, chunk_puts.last.body.bytesize
      assert_equal "bytes 0-#{GraphClient::UPLOAD_CHUNK_SIZE - 1}/#{big.bytesize}",
                   chunk_puts.first.headers["Content-Range"]
      assert_equal "bytes #{GraphClient::UPLOAD_CHUNK_SIZE}-#{big.bytesize - 1}/#{big.bytesize}",
                   chunk_puts.last.headers["Content-Range"]
    end

    test "surfaces the Graph error code and message from the body" do
      client, = build_client([
        token_response,
        [ 400, { error: { code: "ErrorInvalidRecipients", message: "bad address" } }.to_json ]
      ])

      error = assert_raises(GraphAuth::Error) do
        client.create_draft(mailbox: "s@x", to: [ "nope" ], subject: "s", html: "b", attachments: [])
      end
      assert_includes error.message, "ErrorInvalidRecipients"
      assert_includes error.message, "bad address"
    end

    test "list_folder_contents maps folders and files" do
      client, = build_client([
        token_response,
        [ 200, { value: [ { "id" => "1", "name" => "Receipts", "folder" => {}, "webUrl" => "u1" },
                          { "id" => "2", "name" => "note.txt", "webUrl" => "u2" } ] }.to_json ]
      ])

      items = client.list_folder_contents(drive_id: "drv")

      assert_equal [ true, false ], items.map(&:folder)
      assert_equal %w[Receipts note.txt], items.map(&:name)
    end

    test "list_folder_contents follows @odata.nextLink instead of truncating to the first page" do
      client, http = build_client([
        token_response,
        [ 200, { value: [ { "id" => "1", "name" => "a.pdf", "webUrl" => "u1" } ],
                "@odata.nextLink" => "https://graph.microsoft.com/v1.0/next-page" }.to_json ],
        [ 200, { value: [ { "id" => "2", "name" => "b.pdf", "webUrl" => "u2" } ] }.to_json ]
      ])

      items = client.list_folder_contents(drive_id: "drv")

      assert_equal %w[a.pdf b.pdf], items.map(&:name)
      assert_includes http.requests.last.uri, "next-page"
    end

    test "get_site resolves a site URL to its Graph id via the path form" do
      client, http = build_client([
        token_response,
        [ 200, { id: "tenant,guid1,guid2", displayName: "Finance",
                 webUrl: "https://tenant.sharepoint.com/sites/Finance" }.to_json ]
      ])

      site = client.get_site("https://tenant.sharepoint.com/sites/Finance")

      assert_equal "tenant,guid1,guid2", site.id
      assert_equal "Finance", site.name
      # Sites.Selected can't search, so the site is addressed by server-relative path.
      assert_includes http.requests.last.uri, "/sites/tenant.sharepoint.com:/sites/Finance"
    end

    test "list_drives maps each drive, defaulting an unnamed one to Documents" do
      client, http = build_client([
        token_response,
        [ 200, { value: [ { "id" => "drv1", "name" => "Documents" },
                          { "id" => "drv2" } ] }.to_json ]
      ])

      drives = client.list_drives("site-1")

      assert_equal %w[drv1 drv2], drives.map(&:id)
      assert_equal [ "Documents", "Documents" ], drives.map(&:name)
      assert_includes http.requests.last.uri, "/sites/site-1/drives"
    end

    test "list_drives returns an empty array when the site has none" do
      client, = build_client([ token_response, [ 200, {}.to_json ] ])

      assert_empty client.list_drives("site-1")
    end

    test "list_drives follows @odata.nextLink instead of truncating to the first page" do
      client, http = build_client([
        token_response,
        [ 200, { value: [ { "id" => "drv1", "name" => "Documents" } ],
                "@odata.nextLink" => "https://graph.microsoft.com/v1.0/next-page" }.to_json ],
        [ 200, { value: [ { "id" => "drv2", "name" => "Shared" } ] }.to_json ]
      ])

      drives = client.list_drives("site-1")

      assert_equal %w[drv1 drv2], drives.map(&:id)
      assert_includes http.requests.last.uri, "next-page"
    end

    test "check_mailbox probes the mailbox inbox and returns true" do
      client, http = build_client([
        token_response,
        [ 200, { id: "inbox" }.to_json ]
      ])

      assert client.check_mailbox("reimbursements@bedlamfringe.co.uk")
      probe = http.requests.last
      assert_equal "get", probe.method.to_s
      assert_includes probe.uri, "/users/reimbursements@bedlamfringe.co.uk/mailFolders/inbox"
    end

    test "check_mailbox raises when the app can't reach the mailbox" do
      client, = build_client([
        token_response,
        [ 403, { error: { code: "ErrorAccessDenied", message: "Access is denied." } }.to_json ]
      ])

      assert_raises(GraphAuth::AuthError) { client.check_mailbox("locked@bedlamfringe.co.uk") }
    end

    test "check_reachable acquires a token and returns true without touching a resource" do
      client, http = build_client([ token_response ])

      assert client.check_reachable
      # Only the token request was made — no per-resource Graph call.
      assert_equal 1, http.requests.size
      assert_includes http.requests.last.uri, "oauth2/v2.0/token"
    end

    test "check_reachable raises when the token request is rejected" do
      client, = build_client([ [ 401, { error: "invalid_client" }.to_json ] ])

      assert_raises(GraphAuth::AuthError) { client.check_reachable }
    end
  end
end
