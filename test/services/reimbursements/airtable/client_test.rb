require "test_helper"

module Reimbursements
  module Airtable
    class ClientTest < ActiveSupport::TestCase
      include ReimbursementsTestHelpers

      def build_client(responses, sleeps: [])
        http = FakeHttp.new(responses)
        client = Client.new(config: reimbursements_test_config, token: "pat-test",
                            http: http, sleeper: ->(s) { sleeps << s })
        [ client, http ]
      end

      test "lists records across pages with field ids" do
        client, http = build_client([
          [ 200, { records: [ { id: "rec1" } ], offset: "off1" }.to_json ],
          [ 200, { records: [ { id: "rec2" } ] }.to_json ]
        ])

        records = client.list_records(:expenses)

        assert_equal %w[rec1 rec2], records.map { |r| r["id"] }
        assert_equal 2, http.requests.size
        assert_includes http.requests.first.uri, "tblExpenses"
        assert_includes http.requests.first.uri, "returnFieldsByFieldId=true"
        assert_includes http.requests.last.uri, "offset=off1"
        assert_equal "Bearer pat-test", http.requests.first.headers["Authorization"]
      end

      test "creates a record with typecast" do
        client, http = build_client([ [ 200, { id: "recNew", fields: {} }.to_json ] ])

        record = client.create_record(:expenses, { "fldExpAmt" => 12.5 })

        assert_equal "recNew", record["id"]
        body = JSON.parse(http.requests.first.body)
        assert body["typecast"]
        assert body["returnFieldsByFieldId"], "write responses must be field-ID-keyed for the mapper"
        assert_in_delta 12.5, body["fields"]["fldExpAmt"]
        assert_equal "post", http.requests.first.method.to_s
      end

      test "drops a nil-keyed field before writing, rather than sending a malformed field id" do
        client, http = build_client([ [ 200, { id: "recNew", fields: {} }.to_json ] ])

        client.create_record(:expenses, { "fldExpAmt" => 12.5, nil => "unmapped, config lagging behind" })

        body = JSON.parse(http.requests.first.body)
        assert_equal %w[fldExpAmt], body["fields"].keys
      end

      test "deletes a record via DELETE" do
        client, http = build_client([ [ 200, { id: "recExp1", deleted: true }.to_json ] ])

        result = client.delete_record(:expenses, "recExp1")

        assert_equal "recExp1", result["id"]
        request = http.requests.sole
        assert_equal "delete", request.method.to_s
        assert_includes request.uri, "recExp1"
      end

      test "gets a single record and returns nil on 404" do
        client, http = build_client([ [ 200, { id: "recExp1", fields: {} }.to_json ],
                                      [ 404, "{}" ] ])

        assert_equal "recExp1", client.get_record(:expenses, "recExp1")["id"]
        assert_includes http.requests.first.uri, "returnFieldsByFieldId=true"
        assert_nil client.get_record(:expenses, "recGone")
      end

      test "updates a record via patch" do
        client, http = build_client([ [ 200, { id: "recExp1", fields: {} }.to_json ] ])

        client.update_record(:expenses, "recExp1", { "fldExpDesc" => "New" })

        request = http.requests.first
        assert_equal "patch", request.method.to_s
        assert_includes request.uri, "tblExpenses/recExp1"
        assert JSON.parse(request.body)["typecast"]
      end

      test "retries after a 429 with the documented 30s base wait" do
        sleeps = []
        client, http = build_client([ [ 429, "{}" ], [ 200, { records: [] }.to_json ] ], sleeps: sleeps)

        assert_equal [], client.list_records(:people)
        assert_equal [ 30 ], sleeps
        assert_equal 2, http.requests.size
      end

      test "honours a Retry-After header on a 429" do
        sleeps = []
        client, http = build_client([ [ 429, "{}", { "Retry-After" => "5" } ],
                                      [ 200, { records: [] }.to_json ] ], sleeps: sleeps)

        assert_equal [], client.list_records(:people)
        assert_equal [ 5 ], sleeps
        assert_equal 2, http.requests.size
      end

      test "gives up after exhausting retries on repeated 429s" do
        sleeps = []
        client, http = build_client([ [ 429, "{}" ], [ 429, "{}" ], [ 429, "{}" ] ], sleeps: sleeps)

        error = assert_raises(Reimbursements::Airtable::Error) { client.list_records(:people) }
        assert_equal 429, error.status
        assert_equal 3, http.requests.size
        assert_equal [ 30, 60 ], sleeps, "bounded exponential backoff doubling from the 30s base, capped"
      end

      test "never sleeps on a successful response" do
        sleeps = []
        client, = build_client([ [ 200, { records: [] }.to_json ] ], sleeps: sleeps)

        assert_equal [], client.list_records(:people)
        assert_empty sleeps
      end

      test "raises a typed error with status on failure" do
        client, = build_client([ [ 500, "boom" ] ])

        error = assert_raises(Reimbursements::Airtable::Error) { client.list_records(:people) }
        assert_equal 500, error.status
      end

      test "uploads an attachment to the content api as base64" do
        client, http = build_client([ [ 200, { id: "recExp1" }.to_json ] ])

        client.upload_attachment("recExp1", table: :expenses, field: :receipt,
                                 filename: "receipt.pdf", content_type: "application/pdf",
                                 bytes: "PDFBYTES")

        request = http.requests.first
        assert_includes request.uri, "content.airtable.com/v0/appTestBase/recExp1/fldExpRcpt/uploadAttachment"
        body = JSON.parse(request.body)
        assert_equal "receipt.pdf", body["filename"]
        assert_equal "application/pdf", body["contentType"]
        assert_equal "PDFBYTES", Base64.strict_decode64(body["file"])
      end
    end
  end
end
