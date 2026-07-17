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
      RATE_LIMIT_WAIT_SECONDS = 30 # documented Airtable back-off, and the base for our exponential backoff
      MAX_ATTEMPTS = 3 # total tries (1 initial + up to 2 retries) before giving up on a 429
      MAX_WAIT_SECONDS = 60 # cap on a single back-off sleep, so an exponential/Retry-After value can't run away
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

      # returnFieldsByFieldId on writes too: the response is otherwise keyed
      # by field NAME and the mapper would hydrate blank POROs from it.
      def create_record(table, fields_by_id)
        uri = URI("#{API_URL}/#{@config.base_id}/#{@config.table_id(table)}")
        request(:post, uri, { fields: known_fields(fields_by_id), typecast: true, returnFieldsByFieldId: true })
      end

      def update_record(table, record_id, fields_by_id)
        uri = URI("#{API_URL}/#{@config.base_id}/#{@config.table_id(table)}/#{record_id}")
        request(:patch, uri, { fields: known_fields(fields_by_id), typecast: true, returnFieldsByFieldId: true })
      end

      # Drop any nil-keyed entry — a field whose id isn't in this environment's
      # credentials (Config#fid returned nil) — so a lagging config never sends
      # a malformed write rather than just omitting the unknown field.
      def known_fields(fields_by_id)
        fields_by_id.reject { |field_id, _| field_id.nil? }
      end

      # Single-record fetch (1 API call vs re-listing the table); nil on 404.
      def get_record(table, record_id)
        uri = URI("#{API_URL}/#{@config.base_id}/#{@config.table_id(table)}/#{record_id}")
        uri.query = URI.encode_www_form(returnFieldsByFieldId: "true")
        request(:get, uri)
      rescue Error => e
        raise unless e.status == 404

        nil
      end

      # Delete a record (used when reopening a batch for rebuild).
      def delete_record(table, record_id)
        uri = URI("#{API_URL}/#{@config.base_id}/#{@config.table_id(table)}/#{record_id}")
        request(:delete, uri)
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

      # On HTTP 429 we back off and retry, up to MAX_ATTEMPTS total. The wait is
      # the server's Retry-After header when present, otherwise a bounded
      # exponential back-off from RATE_LIMIT_WAIT_SECONDS (doubling per attempt,
      # capped at MAX_WAIT_SECONDS). The @sleeper seam keeps tests instant. The
      # transport may return an optional third element (response headers); the
      # real HttpTransport returns only [status, body], so headers degrade to nil.
      def request(http_method, uri, payload = nil)
        request_headers = { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" }
        body = payload&.to_json
        attempts = 0
        loop do
          attempts += 1
          status, response_body, response_headers = @http.call(http_method, uri, request_headers, body)
          return JSON.parse(response_body) if (200..299).cover?(status)

          if status == 429 && attempts < MAX_ATTEMPTS
            @sleeper.call(retry_wait(response_headers, attempts))
            next
          end

          raise Error.new("Airtable #{http_method.to_s.upcase} #{uri.path} failed " \
                          "(#{status}): #{response_body.to_s.truncate(200)}", status: status)
        end
      end

      # Seconds to wait before the next retry: Retry-After header if the server
      # sent a usable one, else exponential back-off (30, 60, …) capped.
      def retry_wait(response_headers, attempts)
        header_wait = retry_after_seconds(response_headers)
        return [ header_wait, MAX_WAIT_SECONDS ].min if header_wait

        [ RATE_LIMIT_WAIT_SECONDS * (2**(attempts - 1)), MAX_WAIT_SECONDS ].min
      end

      # Parse a Retry-After header (case-insensitive) as an integer number of
      # seconds; nil if absent or not a plain integer (e.g. an HTTP-date form).
      def retry_after_seconds(response_headers)
        return nil unless response_headers.respond_to?(:each)

        pair = response_headers.find { |key, _| key.to_s.casecmp?("retry-after") }
        return nil unless pair

        Integer(pair.last.to_s, exception: false)
      end
    end
  end
end
