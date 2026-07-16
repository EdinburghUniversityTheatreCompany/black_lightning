require "test_helper"

module Reimbursements
  class GraphClientTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    FakeSettings = Struct.new(:azure_tenant_id, :azure_client_id, :azure_client_secret)

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

    test "upload_to_folder refuses an empty file" do
      client, = build_client([ token_response ])
      assert_raises(GraphAuth::Error) do
        client.upload_to_folder(drive_id: "d", folder_id: "f", filename: "x.pdf", content: "")
      end
    end

    test "download fetches bytes without a Graph auth header" do
      client, http = build_client([ [ 200, "RECEIPTBYTES" ] ])

      assert_equal "RECEIPTBYTES", client.download("https://airtable.example/signed")
      assert_nil http.requests.sole.headers["Authorization"]
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
