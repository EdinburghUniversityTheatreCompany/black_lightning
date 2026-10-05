module Reimbursements
  ##
  # Fills EUSA's international payment request form, one payment per file. Only
  # the payment cells are ours; the cashflow, authorisation and bank blocks are
  # EUSA's, signed by hand.
  #
  # * The authorisation formulas (C19/C20/E19) pick the signatory from the
  #   amount in C10, so it must be written as a NUMBER: a string breaks all
  #   three and hands EUSA a form naming no authoriser.
  # * Cells are written with change_contents, never add_cell, which drops the
  #   template's style. (BacsXlsx still has this bug on its amount column.)
  #
  # The formulas compare against GBP thresholds whatever the currency. That is
  # EUSA's rule, and left alone.
  class InternationalXlsx
    # +amount+ is in +currency+ (what EUSA's bank pays), NOT the GBP the budget counts.
    Payment = Struct.new(:payee_name, :amount, :currency, :description, :date_required,
                         :nominal_code, :cost_centre, :bic, :iban,
                         keyword_init: true)

    SHEET_NAME = "FORM".freeze

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

    # Excel's builtin text number format.
    TEXT_FORMAT = "@".freeze
    # For a non-sterling amount: the template's amount cell has a hardcoded "£",
    # which printed a EUR payment as "£266.69" above a cell saying EUR.
    PLAIN_AMOUNT_FORMAT = "#,##0.00".freeze
    STERLING = "GBP".freeze

    DEFAULT_TEMPLATE_PATH =
      Rails.root.join("lib/reimbursements/templates/EUSA_international_payment_template.xlsx").freeze

    class TemplateError < StandardError; end

    def initialize(template_path: DEFAULT_TEMPLATE_PATH)
      @template_path = Pathname(template_path)
      return if @template_path.exist?

      raise TemplateError, "international payment template not found at #{@template_path}"
    end

    # Re-reads the template on every call, so one instance builds many forms.
    # +format_iban+ groups the IBAN in fours, as a human checks it against an invoice.
    def generate(payment, format_iban: false)
      # Not at file scope: eager loading would pull rubyXL into every process.
      require "rubyXL"
      require "rubyXL/convenience_methods"

      validate!(payment)

      workbook = RubyXL::Parser.parse(@template_path.to_s)
      sheet = workbook[SHEET_NAME]
      unless sheet
        raise TemplateError,
              "template has no '#{SHEET_NAME}' sheet (found: #{workbook.worksheets.map(&:sheet_name).inspect})"
      end

      write_form(sheet, payment, format_iban: format_iban)
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
      if payment.cost_centre.blank?
        raise TemplateError, "an international payment needs a cost-centre code before the form can be built."
      end

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

    def write_form(sheet, payment, format_iban:)
      # Submitter free text is formula-sanitised, as in the BACS spreadsheet.
      write(sheet, CELL_PAYEE, CellSanitizer.sanitize(payment.payee_name))
      write(sheet, CELL_DESCRIPTION, CellSanitizer.sanitize(payment.description))
      currency = payment.currency.to_s.strip.upcase
      # Numeric, so the three authorisation formulas can compare against it.
      write(sheet, CELL_AMOUNT, payment.amount.to_f)
      apply_amount_format(sheet, currency)
      text(sheet, CELL_CURRENCY, currency)
      write(sheet, CELL_DATE_REQUIRED, payment.date_required)
      write(sheet, CELL_NOMINAL_CODE, CellSanitizer.sanitize(payment.nominal_code))
      write(sheet, CELL_COST_CENTRE, CellSanitizer.sanitize(payment.cost_centre))

      iban = BankDetails.normalize_iban(payment.iban)
      iban = BankDetails.format_iban(iban) if format_iban
      text(sheet, CELL_BIC, BankDetails.normalize_bic(payment.bic))
      text(sheet, CELL_IBAN, iban)
    end

    # change_contents keeps the template's style; add_cell would drop it. The
    # fallback only guards against a re-vendored template missing a cell.
    def write(sheet, (row, column), value)
      cell = sheet[row] && sheet[row][column]
      return cell.change_contents(value) if cell

      sheet.add_cell(row, column, value)
    end

    # Sterling keeps the template's "£" format, which is then right (a supplier
    # can invoice in GBP).
    def apply_amount_format(sheet, currency)
      return if currency == STERLING

      sheet[CELL_AMOUNT.first][CELL_AMOUNT.last].set_number_format(PLAIN_AMOUNT_FORMAT)
    end

    # Pinned to text: the BIC and IBAN cells carry leftover sort-code and
    # account-number number formats.
    def text(sheet, coordinates, value)
      write(sheet, coordinates, value)
      cell = sheet[coordinates.first][coordinates.last]
      cell.set_number_format(TEXT_FORMAT)
      cell
    end
  end
end
