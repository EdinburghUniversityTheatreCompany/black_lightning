require "test_helper"

module Reimbursements
  class MailboxClientTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    def messages_response(messages)
      [ 200, { value: messages }.to_json ]
    end

    setup do
      # Folder ids are cached across job runs in Rails.cache (a FileStore in test): don't leak
      # them between tests.
      Rails.cache.delete_matched("reimbursements/graph-folder/*")
    end

    def build_client(responses, clock: -> { Time.zone.local(2026, 7, 9, 12) }, sleeper: nil)
      http = FakeHttp.new(responses)
      client = Graph::MailboxClient.new(mailbox: "reimbursements@example.com", settings: graph_settings,
                                 http: http, clock: clock, sleeper: sleeper)
      [ client, http ]
    end

    test "fetches a token once and lists unread messages" do
      raw = { id: "msg1", subject: "Receipt", bodyPreview: "see attached", from: { emailAddress: { address: "PAT@Example.com" } } }
      client, http = build_client([ graph_token_response, messages_response([ raw ]),
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
      client, http = build_client([
        [ 200, { access_token: "tok-1", expires_in: 100 }.to_json ],
        messages_response([]),
        [ 200, { access_token: "tok-2", expires_in: 3600 }.to_json ],
        messages_response([])
      ], clock: -> { now })

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
      client, = build_client([ graph_token_response, [ 200, { value: value }.to_json ] ])

      attachments = client.attachments("msg1")

      assert_equal [ "receipt.pdf", "logo.png", "pasted-receipt.png" ], attachments.map { |a| a[:filename] },
                   "all file attachments and inline images count; only attached items are skipped"
      assert_equal "PDF", attachments.first[:bytes]
    end

    test "reply posts a comment" do
      client, http = build_client([ graph_token_response, [ 202, "" ] ])

      client.reply("msg1", html: "<p>Thanks!</p>")

      request = http.requests.last
      assert_includes request.uri, "/messages/msg1/reply"
      assert_equal "<p>Thanks!</p>", JSON.parse(request.body)["comment"]
    end

    test "reply/move/mark_read are suppressed (no Graph mutation) when outbound is disabled" do
      client, http = build_client([ graph_token_response ])

      without_outbound do
        assert_nil client.reply("msg1", html: "<p>hi</p>")
        assert_nil client.move("msg1", :processed)
        assert_nil client.mark_read("msg1")
      end

      assert_empty http.requests, "no outbound Graph call (not even a token) when outbound is disabled"
    end

    test "mark_read_and_move moves to an existing folder, then marks read" do
      # Moves first: a move failure must leave the message unread (safe to retry on this reject
      # path), not read-but-unfiled for ever.
      client, http = build_client([
        graph_token_response,
        [ 200, { value: [ { id: "fld-processed" } ] }.to_json ],    # folder lookup
        [ 201, { id: "moved" }.to_json ],                           # move
        [ 200, "" ]                                                # PATCH isRead
      ])

      client.mark_read_and_move("msg1", :processed)

      lookup, move, patch = http.requests.last(3)
      assert_includes lookup.uri, "mailFolders"
      assert_equal "post", move.method.to_s
      assert_includes move.uri, "messages/msg1/move"
      assert_equal "fld-processed", JSON.parse(move.body)["destinationId"]
      assert_equal "patch", patch.method.to_s
      assert_includes patch.uri, "messages/msg1"
      assert JSON.parse(patch.body)["isRead"]
    end

    test "creates the folder when missing and memoizes its id" do
      client, http = build_client([
        graph_token_response,
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

    test "raises AuthError when graph rejects the token" do
      client, = build_client([ graph_token_response, [ 401, "expired" ] ])

      assert_raises(GraphAuth::AuthError) { client.unread_messages }
    end

    # Graph's own gateway answers 502/503/504 for a moment now and then; one
    # 502 on each of two mailboxes reached Honeybadger on 23 Sep 2026.
    [ 502, 503, 504 ].each do |status|
      test "a GET answered #{status} is retried once after a pause" do
        pauses = []
        client, = build_client([ graph_token_response, [ status, "UnknownError" ], messages_response([]) ],
                               sleeper: ->(seconds) { pauses << seconds })

        assert_equal [], client.unread_messages
        assert_equal [ GraphAuth::TRANSIENT_RETRY_DELAY ], pauses
      end
    end

    test "a GET still failing after its retry raises Error with the second status" do
      pauses = []
      client, = build_client([ graph_token_response, [ 502, "UnknownError" ], [ 503, "busy" ] ],
                             sleeper: ->(seconds) { pauses << seconds })

      error = assert_raises(GraphAuth::Error) { client.unread_messages }
      assert_includes error.message, "(503)"
      assert_equal 1, pauses.size
    end

    test "a 500 is not retried: it is Graph refusing the request, not its gateway" do
      pauses = []
      client, = build_client([ graph_token_response, [ 500, "boom" ] ], sleeper: ->(seconds) { pauses << seconds })

      assert_raises(GraphAuth::Error) { client.unread_messages }
      assert_empty pauses
    end

    test "a write answered 502 is not retried, since the first attempt may have landed" do
      pauses = []
      client, = build_client([ graph_token_response, [ 502, "UnknownError" ] ], sleeper: ->(seconds) { pauses << seconds })

      assert_raises(GraphAuth::Error) { client.reply("msg1", html: "<p>Thanks</p>") }
      assert_empty pauses
    end

    test "a bare graph_request 404 raises NotFoundError (loud, for non-mutation paths)" do
      # unread_messages is a read path: a 404 there is a real problem and must surface.
      client, = build_client([ graph_token_response, [ 404, GRAPH_ITEM_NOT_FOUND ] ])

      error = assert_raises(GraphAuth::NotFoundError) { client.unread_messages }
      assert_kind_of GraphAuth::Error, error, "NotFoundError must be a subclass of Error"
      assert_match(/ErrorItemNotFound/, error.message)
    end

    # --- A 404 does NOT prove the message is gone ----------------------------
    # Exchange changes a message's id on move, so a mutation can 404 on a message still sitting
    # unread in the mailbox. A blanket swallow turns that into silence: no reply, no Honeybadger
    # notice, no duplicate_risk flag. So a 404 is swallowed only once a re-GET also 404s.
    MUTATIONS = {
      reply: [ [], "post", "messages/msg1/reply", ->(c) { c.reply("msg1", html: "<p>hi</p>") } ],
      mark_read: [ [], "patch", "messages/msg1", ->(c) { c.mark_read("msg1") } ],
      move: [ [ [ 200, { value: [ { id: "fld-processed" } ] }.to_json ] ], "post", "messages/msg1/move",
              ->(c) { c.move("msg1", :processed) } ]
    }.freeze

    MUTATIONS.each do |name, (prefix, verb, path, call)|
      test "#{name} swallows a 404 once a re-GET confirms the message is gone" do
        client, http = build_client([ graph_token_response, *prefix, [ 404, GRAPH_ITEM_NOT_FOUND ], [ 404, GRAPH_ITEM_NOT_FOUND ] ])

        assert_nil call.(client)
        attempted = http.requests[-2]
        assert_equal verb, attempted.method.to_s, "the mutation was still attempted"
        assert_includes attempted.uri, path
        assert_equal "get", http.requests.last.method.to_s
      end

      test "#{name} stays loud when the message still exists" do
        client, = build_client([ graph_token_response, *prefix, [ 404, GRAPH_ITEM_NOT_FOUND ], [ 200, { id: "msg1" }.to_json ] ])

        error = assert_raises(GraphAuth::NotFoundError) { call.(client) }
        assert_match(/ErrorItemNotFound/, error.message)
      end
    end

    # An inconclusive confirmation (5xx, timeout, auth) fails CLOSED: treated as still present,
    # taking the loud path.
    test "an inconclusive existence check keeps the 404 loud" do
      client, = build_client([
        graph_token_response,
        [ 404, GRAPH_ITEM_NOT_FOUND ], # mark_read -> 404
        [ 500, "boom" ]          # confirmation inconclusive
      ])

      assert_raises(GraphAuth::NotFoundError) { client.mark_read("msg1") }
    end

    # A 404 from the FOLDER lookup must not read as "message gone": it is a mailbox setup problem.
    test "a 404 from the folder lookup is not mislabelled as the message being gone" do
      client, http = build_client([
        graph_token_response,
        [ 404, GRAPH_ITEM_NOT_FOUND ] # the mailFolders lookup itself 404s
      ])

      error = assert_raises(GraphAuth::NotFoundError) { client.move("msg1", :processed) }
      assert_match(%r{mailFolders}, error.message, "the error names the folder request, not the message")
      assert_equal 2, http.requests.size, "no message-scoped call and no existence probe was made"
    end
  end
end
