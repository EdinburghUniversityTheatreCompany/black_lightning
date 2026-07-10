module Reimbursements
  ##
  # Extracts expense details from receipt files with Gemini so the portal can
  # prefill the submission form (and email-in can fill what it confidently
  # knows). Extraction failing must never block a submission: this class never
  # raises — transient errors retry with exponential backoff (5 attempts),
  # then callers get an +ok?: false+ result and proceed without prefill.
  class Extractor
    MODEL = "gemini-2.5-flash".freeze
    API_URL = "https://generativelanguage.googleapis.com/v1beta/models/#{MODEL}:generateContent".freeze
    MAX_ATTEMPTS = 5
    BACKOFF_SECONDS = [ 1, 2, 4, 8 ].freeze
    RETRYABLE_STATUSES = [ 429, 500, 502, 503, 504 ].freeze
    TRANSPORT_ERRORS = [ SocketError, Timeout::Error, Errno::ECONNRESET, Errno::ECONNREFUSED,
                        OpenSSL::SSL::SSLError, Net::OpenTimeout, Net::ReadTimeout ].freeze
    REFERENCE_LIMIT = ExpenseForm::REFERENCE_LIMIT

    Extraction = Struct.new(:merchant, :purchase_date, :total_amount, :vat_amount,
                            :vat_itemised, :suggested_description,
                            :suggested_budget_record_id, :suggested_payment_reference,
                            :error, keyword_init: true) do
      def ok?
        error.nil?
      end

      # The amount that actually leaves the submitter's budget. Only derived
      # when the receipt itemises VAT; callers pick their own fallback.
      def amount_excl_vat
        return nil unless vat_itemised && total_amount && vat_amount

        total_amount - vat_amount
      end
    end

    # max_attempts: 5 suits the background poll job; interactive callers
    # (the form's extract endpoint) pass a lower number so a Gemini outage
    # doesn't pin a Puma worker through the whole retry ladder.
    def initialize(api_key: nil, http: nil, sleeper: nil, max_attempts: MAX_ATTEMPTS)
      @api_key = api_key || Settings.gemini_api_key
      @http = http || HttpTransport
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @max_attempts = max_attempts.clamp(1, MAX_ATTEMPTS)
    end

    # receipts: [{filename:, content_type:, bytes:}], budgets: [Budget],
    # context: optional free text (e.g. the email subject/body).
    def extract(receipts:, budgets:, context: nil)
      return failure("no Gemini API key configured") if @api_key.blank?
      return failure("no receipts provided") if receipts.blank?

      response = post_with_retries(request_body(receipts, budgets, context))
      return response if response.is_a?(Extraction)

      parse(response, budgets)
    end

    private

    def failure(message)
      Extraction.new(error: message)
    end

    def request_body(receipts, budgets, context)
      parts = [ { text: prompt(budgets, context) } ]
      receipts.each do |receipt|
        parts << { inline_data: { mime_type: receipt[:content_type],
                                  data: Base64.strict_encode64(receipt[:bytes]) } }
      end
      {
        contents: [ { parts: parts } ],
        generationConfig: { response_mime_type: "application/json", response_schema: response_schema }
      }
    end

    def prompt(budgets, context)
      budget_lines = budgets.map { |b| "- #{b.record_id}: #{b.name}" }.join("\n")
      <<~PROMPT
        You are helping a student theatre producer submit an expense claim from the
        attached receipt(s). Extract what the receipt actually shows; leave fields
        out when you are not confident.

        - total_amount: the total paid in GBP (incl. VAT if charged).
        - vat_itemised: true only if the receipt explicitly itemises VAT (a VAT
          amount or rate with a VAT registration number). Till receipts often don't.
        - vat_amount: the VAT shown, if itemised.
        - purchase_date: ISO 8601.
        - suggested_description: one short line saying what was bought (not the shop's
          marketing text).
        - suggested_budget_record_id: the record id of the best-fitting budget from
          this list, or omit if none fits clearly:
        #{budget_lines}
        - suggested_payment_reference: max #{REFERENCE_LIMIT} characters. If the
          receipt is an invoice specifying a payment reference, use that; otherwise
          use the invoice number; otherwise a short "<merchant or purpose>" label.
        #{context.present? ? "\nContext from the submitter:\n#{context}" : ''}
      PROMPT
    end

    def response_schema
      {
        type: "OBJECT",
        properties: {
          merchant: { type: "STRING" },
          purchase_date: { type: "STRING" },
          total_amount: { type: "NUMBER" },
          vat_amount: { type: "NUMBER" },
          vat_itemised: { type: "BOOLEAN" },
          suggested_description: { type: "STRING" },
          suggested_budget_record_id: { type: "STRING" },
          suggested_payment_reference: { type: "STRING" }
        }
      }
    end

    def post_with_retries(body)
      uri = URI("#{API_URL}?key=#{@api_key}")
      headers = { "Content-Type" => "application/json" }
      json = body.to_json # serialized once — it embeds every receipt as base64
      last_error = nil

      @max_attempts.times do |attempt|
        @sleeper.call(BACKOFF_SECONDS[attempt - 1]) if attempt.positive?
        begin
          status, response_body = @http.call(:post, uri, headers, json)
        rescue *TRANSPORT_ERRORS => e
          last_error = "#{e.class}: #{e.message}"
          next
        end
        return JSON.parse(response_body) if (200..299).cover?(status)

        last_error = "Gemini responded #{status}"
        break unless RETRYABLE_STATUSES.include?(status)
      end

      failure(last_error || "Gemini request failed")
    rescue JSON::ParserError => e
      failure("unparseable Gemini response: #{e.message}")
    end

    def parse(response, budgets)
      text = response.dig("candidates", 0, "content", "parts", 0, "text")
      return failure("empty Gemini response") if text.blank?

      data = JSON.parse(text)
      return failure("Gemini returned a non-object payload") unless data.is_a?(Hash)

      Extraction.new(
        merchant: data["merchant"].presence,
        purchase_date: date(data["purchase_date"]),
        total_amount: decimal(data["total_amount"]),
        vat_amount: decimal(data["vat_amount"]),
        vat_itemised: data["vat_itemised"],
        suggested_description: data["suggested_description"].presence,
        suggested_budget_record_id: known_budget_id(data["suggested_budget_record_id"], budgets),
        suggested_payment_reference: data["suggested_payment_reference"].to_s.strip.first(REFERENCE_LIMIT).presence
      )
    rescue JSON::ParserError => e
      failure("unparseable extraction payload: #{e.message}")
    end

    def known_budget_id(record_id, budgets)
      budgets.map(&:record_id).include?(record_id) ? record_id : nil
    end

    def decimal(value)
      return nil if value.nil?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end

    def date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
