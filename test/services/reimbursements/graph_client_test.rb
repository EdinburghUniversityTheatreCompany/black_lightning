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

    test "create_draft inlines small attachments and returns the webLink" do
      client, http = build_client([
        token_response,
        [ 201, { id: "msg-1", webLink: "https://outlook.example/msg-1" }.to_json ]
      ])

      link = client.create_draft(mailbox: "send@bedlamfringe.co.uk",
                                 to: [ "  finance@eusa.ed.ac.uk ", "" ],
                                 subject: "BACS", html: "<p>hi</p>",
                                 attachments: [ attachment("PDFBYTES", name: "bacs.xlsx") ])

      assert_equal "https://outlook.example/msg-1", link
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
  end
end
