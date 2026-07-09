require "test_helper"

module Reimbursements
  class MailboxClientTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    FakeSettings = Struct.new(:azure_tenant_id, :azure_client_id, :azure_client_secret)

    def settings
      FakeSettings.new("tenant-1", "client-1", "secret-1")
    end

    def token_response(expires_in: 3600)
      [ 200, { access_token: "tok-1", expires_in: expires_in }.to_json ]
    end

    def messages_response(messages)
      [ 200, { value: messages }.to_json ]
    end

    def build_client(responses)
      http = FakeHttp.new(responses)
      client = MailboxClient.new(mailbox: "reimbursements@example.com", settings: settings,
                                 http: http, clock: -> { Time.zone.local(2026, 7, 9, 12) })
      [ client, http ]
    end

    test "fetches a token once and lists unread messages" do
      raw = { id: "msg1", subject: "Receipt", bodyPreview: "see attached",
              hasAttachments: true, from: { emailAddress: { address: "PAT@Example.com" } } }
      client, http = build_client([ token_response, messages_response([ raw ]),
                                    messages_response([]) ])

      messages = client.unread_messages
      client.unread_messages

      assert_equal 1, messages.size
      assert_equal "pat@example.com", messages.first.from_address
      assert messages.first.has_attachments

      token_requests = http.requests.count { |r| r.uri.include?("login.microsoftonline.com") }
      assert_equal 1, token_requests, "token must be cached between calls"
      assert_includes http.requests[1].uri, "isRead+eq+false"
      assert_equal "Bearer tok-1", http.requests[1].headers["Authorization"]
    end

    test "attachments decodes file attachments and skips inline/items" do
      value = [
        { "@odata.type" => "#microsoft.graph.fileAttachment", "name" => "receipt.pdf",
          "contentType" => "application/pdf", "contentBytes" => Base64.strict_encode64("PDF") },
        { "@odata.type" => "#microsoft.graph.fileAttachment", "name" => "logo.png",
          "contentType" => "image/png", "isInline" => true,
          "contentBytes" => Base64.strict_encode64("PNG") },
        { "@odata.type" => "#microsoft.graph.itemAttachment", "name" => "fwd" }
      ]
      client, = build_client([ token_response, [ 200, { value: value }.to_json ] ])

      attachments = client.attachments("msg1")

      assert_equal [ "receipt.pdf" ], attachments.map { |a| a[:filename] }
      assert_equal "PDF", attachments.first[:bytes]
    end

    test "reply posts a comment" do
      client, http = build_client([ token_response, [ 202, "" ] ])

      client.reply("msg1", html: "<p>Thanks!</p>")

      request = http.requests.last
      assert_includes request.uri, "/messages/msg1/reply"
      assert_equal "<p>Thanks!</p>", JSON.parse(request.body)["comment"]
    end

    test "mark_read_and_move marks read then moves to an existing folder" do
      client, http = build_client([
        token_response,
        [ 200, "" ],                                                # PATCH isRead
        [ 200, { value: [ { id: "fld-processed" } ] }.to_json ],    # folder lookup
        [ 201, { id: "moved" }.to_json ]                            # move
      ])

      client.mark_read_and_move("msg1", :processed)

      patch, lookup, move = http.requests.last(3)
      assert_equal "patch", patch.method.to_s
      assert JSON.parse(patch.body)["isRead"]
      assert_includes lookup.uri, "mailFolders"
      assert_equal "fld-processed", JSON.parse(move.body)["destinationId"]
    end

    test "creates the folder when missing and memoizes its id" do
      client, http = build_client([
        token_response,
        [ 200, "" ],
        [ 200, { value: [] }.to_json ],                 # lookup: missing
        [ 201, { id: "fld-new" }.to_json ],             # create folder
        [ 201, { id: "moved" }.to_json ],               # move
        [ 200, "" ],
        [ 201, { id: "moved2" }.to_json ]               # second move reuses folder id
      ])

      client.mark_read_and_move("msg1", :rejected)
      client.mark_read_and_move("msg2", :rejected)

      creates = http.requests.count { |r| r.body.to_s.include?("displayName") }
      assert_equal 1, creates
    end

    test "raises AuthError when the token request is rejected" do
      client, = build_client([ [ 401, { error: "invalid_client" }.to_json ] ])

      assert_raises(MailboxClient::AuthError) { client.unread_messages }
    end

    test "raises AuthError when graph rejects the token" do
      client, = build_client([ token_response, [ 401, "expired" ] ])

      assert_raises(MailboxClient::AuthError) { client.unread_messages }
    end

    test "raises Error on other graph failures" do
      client, = build_client([ token_response, [ 500, "boom" ] ])

      assert_raises(MailboxClient::Error) { client.unread_messages }
    end
  end
end
