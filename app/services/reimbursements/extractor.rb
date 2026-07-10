module Reimbursements
  ##
  # Extracts expense details from receipt files with Gemini so the portal can
  # prefill the submission form (and email-in can fill what it confidently
  # knows). Extraction failing must never block a submission: this class never
  # raises — RubyLLM owns the network retries/back-off, and anything that still
  # goes wrong is captured into an +ok?: false+ result so callers proceed
  # without prefill.
  #
  # Backed by Gemini through RubyLLM (the same gem the operator AiChecker uses),
  # with a validated structured-output schema and multimodal receipt
  # attachments. +chat_builder+ is the injection seam: tests pass a fake chat so
  # no real Gemini call is made.
  class Extractor
    MODEL = "gemini-2.5-flash".freeze
    # Kept for API compatibility with callers that tune retry aggressiveness
    # (the poll job vs an interactive request); RubyLLM now owns the retry ladder.
    MAX_ATTEMPTS = 5
    REFERENCE_LIMIT = ExpenseForm::REFERENCE_LIMIT

    # Structured output the model must return. Every field is optional: the
    # model leaves out anything it isn't confident about, and callers pick their
    # own fallbacks.
    SCHEMA = RubyLLM::Schema.create do
      string :merchant, required: false
      string :purchase_date, required: false
      number :total_amount, required: false
      number :vat_amount, required: false
      boolean :vat_itemised, required: false
      string :suggested_description, required: false
      string :suggested_budget_record_id, required: false
      string :suggested_payment_reference, required: false
    end

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

    # max_attempts is retained for caller compatibility (see MAX_ATTEMPTS).
    def initialize(api_key: nil, chat_builder: nil, max_attempts: MAX_ATTEMPTS)
      @api_key = api_key.nil? ? Settings.gemini_api_key : api_key
      @chat_builder = chat_builder || -> { RubyLLM.chat(model: MODEL) }
      @max_attempts = max_attempts
    end

    # receipts: [{filename:, content_type:, bytes:}], budgets: [Budget],
    # context: optional free text (e.g. the email subject/body).
    def extract(receipts:, budgets:, context: nil)
      return failure("no Gemini API key configured") if @api_key.blank?
      return failure("no receipts provided") if receipts.blank?

      response = @chat_builder.call
                             .with_schema(SCHEMA)
                             .ask(prompt(budgets, context), with: attachments(receipts))
      parse(response.content, budgets)
    rescue RubyLLM::Error => e
      failure("Gemini request failed: #{e.message}")
    rescue StandardError => e
      failure("extraction failed: #{e.message}")
    end

    private

    def failure(message)
      Extraction.new(error: message)
    end

    # In-memory receipt bytes become RubyLLM attachments; the filename carries
    # the extension RubyLLM uses to detect the MIME type.
    def attachments(receipts)
      receipts.map do |receipt|
        RubyLLM::Attachment.new(StringIO.new(receipt[:bytes].to_s), filename: receipt[:filename])
      end
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

    def parse(data, budgets)
      return failure("Gemini returned no structured data") unless data.is_a?(Hash)

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
