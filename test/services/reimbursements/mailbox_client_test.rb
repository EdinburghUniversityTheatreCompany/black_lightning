require "test_helper"

module Reimbursements
  class MailboxClientTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # Delegates outbound_enabled? to the real Settings so the reply/move/mark_read
    # belt-and-braces guards read the same REIMBURSEMENTS_ENABLE_OUTBOUND seam the
    # suite opts into (test_helper), and a suppression test can delete it.
    FakeSettings = Struct.new(:azure_tenant_id, :azure_client_id, :azure_client_secret) do
      def outbound_enabled?
        Reimbursements::Settings.outbound_enabled?
      end
    end

    def settings
      FakeSettings.new("tenant-1", "client-1", "secret-1")
    end

    def token_response(expires_in: 3600)
      [ 200, { access_token: "tok-1", expires_in: expires_in }.to_json ]
    end

    def messages_response(messages)
      [ 200, { value: messages }.to_json ]
    end

    setup do
      # Folder ids are cached in Rails.cache across job runs; tests must not
      # leak them into each other (the test cache is a FileStore).
      Rails.cache.delete_matched("reimbursements/graph-folder/*")
    end

    def build_client(responses)
      http = FakeHttp.new(responses)
      client = MailboxClient.new(mailbox: "reimbursements@example.com", settings: settings,
                                 http: http, clock: -> { Time.zone.local(2026, 7, 9, 12) })
      [ client, http ]
    end

    test "fetches a token once and lists unread messages" do
      raw = { id: "msg1", subject: "Receipt", bodyPreview: "see attached", from: { emailAddress: { address: "PAT@Example.com" } } }
      client, http = build_client([ token_response, messages_response([ raw ]),
                                    messages_response([]) ])

      messages = client.unread_messages
      client.unread_messages

      assert_equal 1, messages.size
      assert_equal "pat@example.com", messages.first.from_address

      token_requests = http.requests.count { |r| r.uri.include?("login.microsoftonline.com") }
      assert_equal 1, token_requests, "token must be cached between calls"
      assert_includes http.requests[1].uri, "isRead+eq+false"
      assert_equal "Bearer tok-1", http.requests[1].headers["Authorization"]
    end

    test "fetches a fresh token once the cached one has expired" do
      now = Time.zone.local(2026, 7, 9, 12)
      http = FakeHttp.new([
        [ 200, { access_token: "tok-1", expires_in: 100 }.to_json ],
        messages_response([]),
        [ 200, { access_token: "tok-2", expires_in: 3600 }.to_json ],
        messages_response([])
      ])
      client = MailboxClient.new(mailbox: "reimbursements@example.com", settings: settings,
                                 http: http, clock: -> { now })

      client.unread_messages
      now += 200 # well past the first token's 100s expiry
      client.unread_messages

      token_requests = http.requests.select { |r| r.uri.include?("login.microsoftonline.com") }
      assert_equal 2, token_requests.size, "an expired token must trigger a refetch, not be reused"
      list_requests = http.requests.select { |r| r.uri.include?("isRead+eq+false") }
      assert_equal "Bearer tok-1", list_requests.first.headers["Authorization"]
      assert_equal "Bearer tok-2", list_requests.last.headers["Authorization"]
    end

    test "attachments decodes file attachments and skips inline/items" do
      value = [
        { "@odata.type" => "#microsoft.graph.fileAttachment", "name" => "receipt.pdf",
          "contentType" => "application/pdf", "contentBytes" => Base64.strict_encode64("PDF") },
        { "@odata.type" => "#microsoft.graph.fileAttachment", "name" => "logo.png",
          "contentType" => "image/png", "isInline" => true, "size" => 4_096,
          "contentBytes" => Base64.strict_encode64("PNG") },
        { "@odata.type" => "#microsoft.graph.fileAttachment", "name" => "pasted-receipt.png",
          "contentType" => "image/png", "isInline" => true, "size" => 350_000,
          "contentBytes" => Base64.strict_encode64("BIGPNG") },
        { "@odata.type" => "#microsoft.graph.itemAttachment", "name" => "fwd" }
      ]
      client, = build_client([ token_response, [ 200, { value: value }.to_json ] ])

      attachments = client.attachments("msg1")

      assert_equal [ "receipt.pdf", "logo.png", "pasted-receipt.png" ], attachments.map { |a| a[:filename] },
                   "all file attachments and inline images count; only attached items are skipped"
      assert_equal "PDF", attachments.first[:bytes]
    end

    test "reply posts a comment" do
      client, http = build_client([ token_response, [ 202, "" ] ])

      client.reply("msg1", html: "<p>Thanks!</p>")

      request = http.requests.last
      assert_includes request.uri, "/messages/msg1/reply"
      assert_equal "<p>Thanks!</p>", JSON.parse(request.body)["comment"]
    end

    test "reply/move/mark_read are suppressed (no Graph mutation) when outbound is disabled" do
      client, http = build_client([ token_response ])
      original = ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")

      assert_nil client.reply("msg1", html: "<p>hi</p>")
      assert_nil client.move("msg1", :processed)
      assert_nil client.mark_read("msg1")

      assert_empty http.requests, "no outbound Graph call (not even a token) when outbound is disabled"
    ensure
      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = original if original
    end

    test "mark_read_and_move moves to an existing folder, then marks read" do
      # Moves first: a move failure must leave the message unread (safe to
      # retry — no expense exists yet on this reject path), not the reverse,
      # which would leave a read-but-unfiled message stuck forever.
      client, http = build_client([
        token_response,
        [ 200, { value: [ { id: "fld-processed" } ] }.to_json ],    # folder lookup
        [ 201, { id: "moved" }.to_json ],                           # move
        [ 200, "" ]                                                # PATCH isRead
      ])

      client.mark_read_and_move("msg1", :processed)

      lookup, move, patch = http.requests.last(3)
      assert_includes lookup.uri, "mailFolders"
      assert_equal "fld-processed", JSON.parse(move.body)["destinationId"]
      assert_equal "patch", patch.method.to_s
      assert JSON.parse(patch.body)["isRead"]
    end

    test "mark_read patches isRead in isolation (the accept path's separate commit step)" do
      client, http = build_client([ token_response, [ 200, "" ] ])

      client.mark_read("msg1")

      patch = http.requests.last
      assert_equal "patch", patch.method.to_s
      assert_includes patch.uri, "messages/msg1"
      assert JSON.parse(patch.body)["isRead"]
    end

    test "move posts to the destination folder in isolation (the accept path's separate commit step)" do
      client, http = build_client([
        token_response,
        [ 200, { value: [ { id: "fld-processed" } ] }.to_json ], # folder lookup
        [ 201, { id: "moved" }.to_json ]                          # move
      ])

      client.move("msg1", :processed)

      move = http.requests.last
      assert_equal "post", move.method.to_s
      assert_includes move.uri, "messages/msg1/move"
      assert_equal "fld-processed", JSON.parse(move.body)["destinationId"]
    end

    test "creates the folder when missing and memoizes its id" do
      client, http = build_client([
        token_response,
        [ 200, { value: [] }.to_json ],                 # lookup: missing
        [ 201, { id: "fld-new" }.to_json ],             # create folder
        [ 201, { id: "moved" }.to_json ],               # move
        [ 200, "" ],                                    # PATCH isRead
        [ 201, { id: "moved2" }.to_json ],              # second move reuses folder id
        [ 200, "" ]                                     # second PATCH isRead
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

    # The real Graph error body when a message no longer exists (handled or
    # deleted by hand in Outlook between the poll's listing and the mutation).
    ITEM_NOT_FOUND = { error: { code: "ErrorItemNotFound",
                                message: "The specified object was not found in the store." } }.to_json

    test "a bare graph_request 404 raises NotFoundError (loud, for non-mutation paths)" do
      # unread_messages is a read path — a 404 here is a real problem and must
      # still surface. NotFoundError < Error, so existing rescues still catch it.
      client, = build_client([ token_response, [ 404, ITEM_NOT_FOUND ] ])

      error = assert_raises(GraphAuth::NotFoundError) { client.unread_messages }
      assert_kind_of MailboxClient::Error, error, "NotFoundError must be a subclass of Error"
      assert_match(/ErrorItemNotFound/, error.message)
    end

    test "reply swallows a 404 (message confirmed gone) and returns nil" do
      client, http = build_client([
        token_response,
        [ 404, ITEM_NOT_FOUND ], # reply -> 404
        [ 404, ITEM_NOT_FOUND ]  # confirmation re-GET -> also 404, so genuinely gone
      ])

      assert_nil client.reply("msg1", html: "<p>hi</p>"), "a vanished message means nothing to reply to"
      assert_equal "post", http.requests[-2].method.to_s, "the reply was still attempted"
    end

    test "mark_read swallows a 404 (message confirmed gone) and returns nil" do
      client, http = build_client([
        token_response,
        [ 404, ITEM_NOT_FOUND ], # mark_read -> 404
        [ 404, ITEM_NOT_FOUND ]  # confirmation re-GET -> also 404
      ])

      assert_nil client.mark_read("msg1"), "a vanished message is already effectively read"
      assert_equal "patch", http.requests[-2].method.to_s
    end

    test "move swallows a 404 (message confirmed gone) and returns nil" do
      client, http = build_client([
        token_response,
        [ 200, { value: [ { id: "fld-processed" } ] }.to_json ], # folder lookup
        [ 404, ITEM_NOT_FOUND ],                                 # move -> 404
        [ 404, ITEM_NOT_FOUND ]                                  # confirmation re-GET -> also 404
      ])

      assert_nil client.move("msg1", :processed), "a vanished message has nothing to file"
      assert_includes http.requests[-2].uri, "messages/msg1/move"
    end

    # --- S4: a 404 does NOT prove the message is gone ------------------------
    #
    # Exchange CHANGES a message's id when the message is moved, so a mutation can
    # 404 on a message that is still sitting in the mailbox, still unread. The old
    # blanket swallow turned that into silence: the draft was created, mark_read
    # reported success, the reply 404'd so the sender was never told their claim
    # arrived, the move 404'd too, and nothing above logger.info fired — no
    # Honeybadger, no duplicate_risk flag. The email was silently abandoned.

    test "mark_read stays loud when a 404 is contradicted by the message still existing" do
      client, http = build_client([
        token_response,
        [ 404, ITEM_NOT_FOUND ],            # mark_read -> 404
        [ 200, { id: "msg1" }.to_json ]     # but the message IS still there
      ])

      error = assert_raises(GraphAuth::NotFoundError) { client.mark_read("msg1") }
      assert_match(/ErrorItemNotFound/, error.message)
      assert_equal "get", http.requests.last.method.to_s, "existence was actually confirmed"
    end

    test "reply stays loud when the message still exists" do
      client, = build_client([
        token_response,
        [ 404, ITEM_NOT_FOUND ],
        [ 200, { id: "msg1" }.to_json ]
      ])

      assert_raises(GraphAuth::NotFoundError) { client.reply("msg1", html: "<p>hi</p>") }
    end

    test "move stays loud when the message still exists" do
      client, = build_client([
        token_response,
        [ 200, { value: [ { id: "fld-processed" } ] }.to_json ],
        [ 404, ITEM_NOT_FOUND ],
        [ 200, { id: "msg1" }.to_json ]
      ])

      assert_raises(GraphAuth::NotFoundError) { client.move("msg1", :processed) }
    end

    # An inconclusive confirmation (5xx, timeout, auth) must fail CLOSED — treat
    # the message as still present and take the loud path, rather than swallowing
    # a message that may still need processing.
    test "an inconclusive existence check keeps the 404 loud" do
      client, = build_client([
        token_response,
        [ 404, ITEM_NOT_FOUND ], # mark_read -> 404
        [ 500, "boom" ]          # confirmation inconclusive
      ])

      assert_raises(GraphAuth::NotFoundError) { client.mark_read("msg1") }
    end

    # move wrapped folder_id -> find_or_create_folder inside the same rescue, so a
    # 404 from the FOLDER lookup was mislabelled "message gone" and swallowed —
    # hiding a mailbox/folder misconfiguration entirely.
    test "a 404 from the folder lookup is not mislabelled as the message being gone" do
      client, http = build_client([
        token_response,
        [ 404, ITEM_NOT_FOUND ] # the mailFolders lookup itself 404s
      ])

      error = assert_raises(GraphAuth::NotFoundError) { client.move("msg1", :processed) }
      assert_match(%r{mailFolders}, error.message, "the error names the folder request, not the message")
      assert_equal 2, http.requests.size, "no message-scoped call and no existence probe was made"
    end
  end
end
