module Reimbursements
  ##
  # Fills EUSA's international payment request form, one payment per file. Only
  # the payment cells are ours; the cashflow, authorisation and bank blocks are
  # EUSA's, signed by hand.
  #
  # The authorisation formulas (C19/C20/E19) pick the signatory from the amount
  # in C10, so it must be written as a NUMBER: a string breaks all three and
  # hands EUSA a form naming no authoriser.
  #
  # The formulas compare against GBP thresholds whatever the currency. That is
  # EUSA's rule, and left alone.
  class InternationalXlsx
    include XlsxTemplate

    # +amount+ is in +currency+ (what EUSA's bank pays), NOT the GBP the budget counts.
    Payment = Struct.new(:payee_name, :amount, :currency, :description, :date_required,
                         :nominal_code, :cost_centre, :bic, :iban,
                         keyword_init: true)

    SHEET_NAME = "FORM".freeze
    TEMPLATE_LABEL = "international payment template".freeze

    # 0-based [row, column]. EUSA's 2026-09 revision moved every field below the
    # amount down a row: check these against the A1 references after any
    # re-vendoring, or a code lands in the wrong cell silently.
    CELL_PAYEE = [ 7, 2 ].freeze          # C8
    CELL_DESCRIPTION = [ 8, 2 ].freeze    # C9
    CELL_AMOUNT = [ 9, 2 ].freeze         # C10
    CELL_DATE_REQUIRED = [ 9, 4 ].freeze  # E10
    CELL_CURRENCY = [ 10, 2 ].freeze      # C11
    CELL_NOMINAL_CODE = [ 11, 2 ].freeze  # C12
    CELL_COST_CENTRE = [ 11, 4 ].freeze   # E12
    CELL_BIC = [ 12, 2 ].freeze           # C13
    CELL_IBAN = [ 12, 4 ].freeze          # E13

    # For a non-sterling amount: the template's amount cell has a hardcoded "£",
    # which printed a EUR payment as "£266.69" above a cell saying EUR.
    PLAIN_AMOUNT_FORMAT = "#,##0.00".freeze
    STERLING = "GBP".freeze

    DEFAULT_TEMPLATE_PATH =
      Rails.root.join("lib/reimbursements/templates/EUSA_international_payment_template.xlsx").freeze

    # Re-reads the template on every call, so one instance builds many forms.
    def generate(payment)
      validate!(payment)

      workbook, sheet = open_workbook
      write_form(sheet, payment)
      force_recalculation(workbook)
      workbook.stream.string
    end

    private

    # The template caches each formula's value from EUSA's sample payment, so
    # left alone the authorisation formulas show the sample's signatory (a
    # EUR 1,266.69 form would name a Co-ordinator where EUSA's rule wants the
    # Head of Finance). fullCalcOnLoad makes Excel recalculate; the cached
    # values are dropped too because LibreOffice ignores the flag. A blank
    # authoriser prompts a human; a wrong one does not.
    def force_recalculation(workbook)
      workbook.calc_pr ||= RubyXL::CalculationProperties.new
      workbook.calc_pr.full_calc_on_load = true

      workbook.worksheets.each do |sheet|
        sheet.sheet_data.rows.each do |row|
          # raw_value is the <v> element itself; RubyXL::Cell has no value=.
          row&.cells&.each { |cell| cell.raw_value = nil if cell&.formula }
        end
      end
    end

    # Each refusal is a form EUSA could not act on: a wrong form costs days, a
    # refusal a correction before anything is sent.
    def validate!(payment)
      if payment.amount.nil? || payment.amount.to_d.zero?
        raise TemplateError, "an international payment needs a non-zero amount."
      end

      raise TemplateError, "an international payment needs a BIC/SWIFT code." if payment.bic.blank?

      # The form's amount label names no currency, so a blank leaves no unit at all.
      raise TemplateError, "an international payment needs a payment currency." if payment.currency.blank?

      # The last check before EUSA's bank moves the money.
      return if BankDetails.valid_iban?(payment.iban)

      raise TemplateError, "#{payment.iban.presence || 'a blank IBAN'} is not a valid IBAN."
    end

    def write_form(sheet, payment)
      # Submitter free text is formula-sanitised, as in the BACS spreadsheet.
      write(sheet, *CELL_PAYEE, CellSanitizer.sanitize(payment.payee_name))
      write(sheet, *CELL_DESCRIPTION, CellSanitizer.sanitize(payment.description))
      currency = payment.currency.to_s.strip.upcase
      # Numeric, so the three authorisation formulas can compare against it.
      amount = write(sheet, *CELL_AMOUNT, payment.amount.to_f)
      # Sterling keeps the template's "£" format, which is then right (a
      # supplier can invoice in GBP).
      amount.set_number_format(PLAIN_AMOUNT_FORMAT) unless currency == STERLING
      write_text(sheet, *CELL_CURRENCY, currency)
      write(sheet, *CELL_DATE_REQUIRED, payment.date_required)
      write(sheet, *CELL_NOMINAL_CODE, CellSanitizer.sanitize(payment.nominal_code))
      write(sheet, *CELL_COST_CENTRE, CellSanitizer.sanitize(payment.cost_centre))

      write_text(sheet, *CELL_BIC, BankDetails.normalize_bic(payment.bic))
      # Grouped in fours, as a human checks it against an invoice.
      write_text(sheet, *CELL_IBAN, BankDetails.format_iban(BankDetails.normalize_iban(payment.iban)))
    end
  end
end
