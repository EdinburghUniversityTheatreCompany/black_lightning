require "test_helper"

module Reimbursements
  class ExtractorTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    RECEIPT = { filename: "receipt.pdf", content_type: "application/pdf", bytes: "PDF" }.freeze

    def budgets
      [ Budget.new(record_id: "recBud1", name: "Props", nominal_code: "4000") ]
    end

    def gemini_response(payload)
      { candidates: [ { content: { parts: [ { text: payload.to_json } ] } } ] }.to_json
    end

    def build_extractor(responses, sleeps: [])
      http = FakeHttp.new(responses)
      extractor = Extractor.new(api_key: "gem-test", http: http, sleeper: ->(s) { sleeps << s })
      [ extractor, http ]
    end

    def happy_payload
      {
        merchant: "Edinburgh Bargain Stores", purchase_date: "2026-07-01",
        total_amount: 12.5, vat_amount: 2.08, vat_itemised: true,
        suggested_description: "Props for main show",
        suggested_budget_record_id: "recBud1",
        suggested_payment_reference: "A VERY LONG REFERENCE INDEED"
      }
    end

    test "parses a successful extraction" do
      extractor, http = build_extractor([ [ 200, gemini_response(happy_payload) ] ])

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets)

      assert result.ok?
      assert_equal "Edinburgh Bargain Stores", result.merchant
      assert_equal Date.new(2026, 7, 1), result.purchase_date
      assert_equal BigDecimal("12.5"), result.total_amount
      assert_equal BigDecimal("2.08"), result.vat_amount
      assert result.vat_itemised
      assert_equal "recBud1", result.suggested_budget_record_id
      assert_equal 18, result.suggested_payment_reference.length, "reference must be truncated to 18 chars"

      body = JSON.parse(http.requests.sole.body)
      assert_equal "application/pdf", body["contents"].first["parts"].last["inline_data"]["mime_type"]
    end

    test "discards a suggested budget that is not in the provided list" do
      extractor, = build_extractor([ [ 200, gemini_response(happy_payload.merge(suggested_budget_record_id: "recBogus")) ] ])

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets)

      assert result.ok?
      assert_nil result.suggested_budget_record_id
    end

    test "fails gracefully on an unparseable model response" do
      raw = { candidates: [ { content: { parts: [ { text: "not valid json {" } ] } } ] }.to_json
      extractor, = build_extractor([ [ 200, raw ] ])

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets)
      assert_not result.ok?
    end

    test "fails gracefully when the model returns a non-object payload" do
      extractor, = build_extractor([ [ 200, gemini_response("just a string") ] ])

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets)
      assert_not result.ok?
    end

    test "fails without calling the api when no key is configured" do
      result = Extractor.new(api_key: nil, http: FakeHttp.new([])).extract(receipts: [ RECEIPT ], budgets: budgets)

      assert_not result.ok?
      assert_match(/key/i, result.error)
    end

    test "retries transient errors with exponential backoff then succeeds" do
      sleeps = []
      extractor, http = build_extractor(
        [ [ 500, "boom" ], [ 503, "busy" ], [ 200, gemini_response(happy_payload) ] ], sleeps: sleeps
      )

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets)

      assert result.ok?
      assert_equal [ 1, 2 ], sleeps
      assert_equal 3, http.requests.size
    end

    test "gives up after five attempts" do
      sleeps = []
      extractor, http = build_extractor(Array.new(5) { [ 500, "boom" ] }, sleeps: sleeps)

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets)

      assert_not result.ok?
      assert_equal [ 1, 2, 4, 8 ], sleeps
      assert_equal 5, http.requests.size
    end

    test "does not retry non-transient client errors" do
      sleeps = []
      extractor, http = build_extractor([ [ 400, "bad request" ] ], sleeps: sleeps)

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets)

      assert_not result.ok?
      assert_empty sleeps
      assert_equal 1, http.requests.size
    end

    test "retries when the transport raises" do
      calls = 0
      http = lambda do |*_args|
        calls += 1
        raise SocketError, "dns down" if calls == 1

        [ 200, gemini_response(happy_payload) ]
      end
      extractor = Extractor.new(api_key: "gem-test", http: http, sleeper: ->(_s) { })

      assert extractor.extract(receipts: [ RECEIPT ], budgets: budgets).ok?
      assert_equal 2, calls
    end
  end
end
