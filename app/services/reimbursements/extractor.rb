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

    # The everyday fields, shared by both extraction modes. Every field is
    # optional: the model leaves out anything it isn't confident about, and
    # callers pick their own fallbacks. Kept as a proc so the two schemas below
    # declare them once (jscpd duplication gate is at zero).
    BASE_FIELDS = lambda do
      string :merchant, required: false
      string :purchase_date, required: false
      number :total_amount, required: false
      number :vat_amount, required: false
      boolean :vat_itemised, required: false
      string :suggested_description, required: false
      string :suggested_budget_record_id, required: false
      string :suggested_payment_reference, required: false
    end

    # Reimburse-myself mode (the default): merchant/amounts/budget only. No bank
    # details are ever requested — the submitter is paid on their own registered
    # account.
    SCHEMA = RubyLLM::Schema.create { instance_exec(&BASE_FIELDS) }

    # Invoice mode: the claim pays a third party on the bank details PRINTED on
    # the invoice, so the schema additionally returns the payee trio. The model
    # is told to leave them out unless they actually appear on the document; the
    # operator/submitter still verifies, and the modulus/all-or-nothing checks
    # on the override fields are unchanged.
    INVOICE_SCHEMA = RubyLLM::Schema.create do
      instance_exec(&BASE_FIELDS)
      string :payee_name, required: false
      string :sort_code, required: false
      string :account_number, required: false
    end

    Extraction = Struct.new(:merchant, :purchase_date, :total_amount, :vat_amount,
                            :vat_itemised, :suggested_description,
                            :suggested_budget_record_id, :suggested_payment_reference,
                            :payee_name, :sort_code, :account_number,
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

    # receipts: [{filename:, content_type:, bytes:}], budgets: [Budget].
    # mode: :self (reimburse the submitter, the default) or :invoice (pay the
    # bank details printed on the invoice). Only :invoice requests the payee
    # bank trio; :self never does. Extraction is opt-in per receipt — the
    # portal only calls this once the submitter has consented (see the receipt
    # form's consent radios); email-in no longer extracts at all.
    def extract(receipts:, budgets:, mode: :self)
      return failure("no Gemini API key configured") if @api_key.blank?
      return failure("no receipts provided") if receipts.blank?

      invoice = invoice_mode?(mode)
      response = @chat_builder.call
                             .with_schema(invoice ? INVOICE_SCHEMA : SCHEMA)
                             .ask(prompt(budgets, invoice), with: attachments(receipts))
      parse(response.content, budgets, invoice)
    rescue RubyLLM::Error => e
      failure("Gemini request failed: #{e.message}")
    rescue StandardError => e
      failure("extraction failed: #{e.message}")
    end

    private

    def failure(message)
      Extraction.new(error: message)
    end

    def invoice_mode?(mode)
      mode.to_s == "invoice"
    end

    # In-memory receipt bytes become RubyLLM attachments; the filename carries
    # the extension RubyLLM uses to detect the MIME type.
    def attachments(receipts)
      receipts.map do |receipt|
        RubyLLM::Attachment.new(StringIO.new(receipt[:bytes].to_s), filename: receipt[:filename])
      end
    end

    def prompt(budgets, invoice)
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
        #{invoice_block(invoice)}
      PROMPT
    end

    # Invoice mode also asks for the payee's bank details, but ONLY when they are
    # actually printed on the invoice — never inferred or guessed. A supplier
    # invoice usually prints these for a BACS payment; a shop receipt does not.
    def invoice_block(invoice)
      return "" unless invoice

      <<~BLOCK.chomp
        - payee_name: the account name to pay, only if printed on the invoice.
        - sort_code: the payee's UK sort code, only if printed on the invoice.
        - account_number: the payee's account number, only if printed on the invoice.
        Leave payee_name, sort_code and account_number out entirely unless they are
        printed on the invoice. Do not guess or infer them.
      BLOCK
    end

    def parse(data, budgets, invoice)
      return failure("Gemini returned no structured data") unless data.is_a?(Hash)

      attrs = {
        merchant: data["merchant"].presence,
        purchase_date: date(data["purchase_date"]),
        total_amount: decimal(data["total_amount"]),
        vat_amount: decimal(data["vat_amount"]),
        vat_itemised: data["vat_itemised"],
        suggested_description: data["suggested_description"].presence,
        suggested_budget_record_id: known_budget_id(data["suggested_budget_record_id"], budgets),
        suggested_payment_reference: data["suggested_payment_reference"].to_s.strip.first(REFERENCE_LIMIT).presence
      }
      if invoice
        attrs[:payee_name] = data["payee_name"].presence
        attrs[:sort_code] = data["sort_code"].presence
        attrs[:account_number] = data["account_number"].presence
      end
      Extraction.new(**attrs)
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
