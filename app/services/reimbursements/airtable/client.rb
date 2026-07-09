module Reimbursements
  module Airtable
    ##
    # Thin Airtable REST client. Everything is keyed by field ID
    # (+returnFieldsByFieldId+ on reads, field-ID payloads on writes) and
    # +typecast: true+ lets Airtable resolve single-select labels.
    #
    # The Airtable workspace is on the free plan (~1,000 API calls/month shared
    # with bedlam-bacs) — never call this directly from controllers/jobs; go
    # through Reimbursements::Store, which caches.
    #
    # +http+ is an injectable transport callable
    # (method, uri, headers, body) -> [status, body_string] so tests run
    # without webmock (this repo deliberately has no mocking library).
    class Client
      API_URL = "https://api.airtable.com/v0".freeze
      CONTENT_URL = "https://content.airtable.com/v0".freeze
      RATE_LIMIT_WAIT_SECONDS = 30 # documented Airtable back-off after a 429
      PAGE_SIZE = 100

      def initialize(config:, token: nil, http: nil, sleeper: nil)
        @config = config
        @token = token || Settings.airtable_pat
        @http = http || HttpTransport
        @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      end

      def list_records(table)
        records = []
        offset = nil
        loop do
          params = { returnFieldsByFieldId: "true", pageSize: PAGE_SIZE }
          params[:offset] = offset if offset
          uri = URI("#{API_URL}/#{@config.base_id}/#{@config.table_id(table)}")
          uri.query = URI.encode_www_form(params)
          page = request(:get, uri)
          records.concat(page.fetch("records"))
          offset = page["offset"]
          break if offset.blank?
        end
        records
      end

      def create_record(table, fields_by_id)
        uri = URI("#{API_URL}/#{@config.base_id}/#{@config.table_id(table)}")
        request(:post, uri, { fields: fields_by_id, typecast: true })
      end

      def update_record(table, record_id, fields_by_id)
        uri = URI("#{API_URL}/#{@config.base_id}/#{@config.table_id(table)}/#{record_id}")
        request(:patch, uri, { fields: fields_by_id, typecast: true })
      end

      # Uploads receipt bytes straight into an attachment field (≤5 MB per
      # Airtable's content API limit — enforce at the form boundary).
      def upload_attachment(record_id, table:, field:, filename:, content_type:, bytes:)
        field_id = @config.fid(table, field)
        uri = URI("#{CONTENT_URL}/#{@config.base_id}/#{record_id}/#{field_id}/uploadAttachment")
        request(:post, uri, {
          contentType: content_type,
          filename: filename,
          file: Base64.strict_encode64(bytes)
        })
      end

      private

      def request(http_method, uri, payload = nil)
        headers = { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" }
        body = payload&.to_json
        status, response_body = @http.call(http_method, uri, headers, body)
        if status == 429
          @sleeper.call(RATE_LIMIT_WAIT_SECONDS)
          status, response_body = @http.call(http_method, uri, headers, body)
        end
        unless (200..299).cover?(status)
          raise Error.new("Airtable #{http_method.to_s.upcase} #{uri.path} failed " \
                          "(#{status}): #{response_body.to_s.truncate(200)}", status: status)
        end
        JSON.parse(response_body)
      end
    end
  end
end
