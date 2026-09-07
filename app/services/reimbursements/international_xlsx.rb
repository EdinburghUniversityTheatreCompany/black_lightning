module Reimbursements
  ##
  # Fills EUSA's international payment request form — one payment per file,
  # unlike the 200-row domestic BACS spreadsheet BacsXlsx builds.
  #
  # The vendored template is EUSA's own, blanked of the sample payment it
  # arrived with. Only eight cells are ours to write; rows 14-27 are their
  # cashflow, authorisation and bank blocks, signed by hand.
  #
  # Two things about the template drive how this is written:
  #
  # * The three authorisation formulas (C18/C19/E18) pick the signatory from
  #   the amount in C10, so it must be written as a NUMBER. A string there
  #   silently breaks all three and hands EUSA a form naming no authoriser.
  # * Every cell is written with +change_contents+, never +add_cell+.
  #   add_cell REPLACES the cell and drops the style the template applied, so
  #   the amount would lose its currency format. (BacsXlsx has exactly this
  #   bug on its own amount column — see plans/off-topic-improvements.md.)
  #
  # Worth knowing: the authorisation formulas compare the amount against GBP
  # thresholds whatever currency it is in. That is EUSA's, in their template,
  # and is deliberately left alone — this fills their form, it does not correct
  # it. The one presentation change made here is the amount's currency format,
  # for the reason given at PLAIN_AMOUNT_FORMAT.
  class InternationalXlsx
    # One payment destined for one form. +amount+ is in +currency+ (the figure
    # EUSA's bank pays the supplier), NOT the GBP equivalent the budget counts.
    Payment = Struct.new(:payee_name, :amount, :currency, :description, :date_required,
                         :nominal_code, :cost_centre, :bic, :iban,
                         keyword_init: true)

    SHEET_NAME = "FORM".freeze

    # 0-based [row, column] of each cell we fill, matching the template's own
    # B/C/D/E layout: labels in column B and D, values in C and E.
    #
    # EUSA revised the form (vendored 2026-09-07) to add PAYMENT CURRENCY, which
    # pushed everything below the amount down one row. Check these against the
    # A1 references before assuming a future revision left them alone — a wrong
    # one writes a nominal code into the cost-centre cell, silently.
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
    # A plain two-decimal number, for an amount that is not in sterling. The
    # template's amount cell carries a hardcoded "£" copied from the domestic
    # form, which since EUSA added PAYMENT CURRENCY sits directly above a cell
    # saying otherwise — a EUR 266.69 payment rendered "£266.69" next to "EUR".
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

    # Render one form as bytes, ready to attach to the EUSA draft or upload to
    # SharePoint. The template is re-read on every call so one instance can
    # produce a whole batch's worth of forms without state bleed.
    #
    # +format_iban+ groups the IBAN in fours the way a bank prints it, which is
    # how a human checks it against an invoice.
    def generate(payment, format_iban: false)
      # Loaded here rather than at file scope: this class is eager-loaded in
      # production, so a top-level require would pull rubyXL into every process
      # at boot even though only a batch build touches it (Gemfile require:false).
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

    # Make every reader recalculate, and leave nothing stale behind if one
    # will not.
    #
    # xlsx caches each formula's last computed value beside the formula, and
    # the template's cached values are the ones EUSA's sample payment produced.
    # Writing a new amount does not update them, so left alone the three
    # authorisation formulas RENDER the sample's answer: a EUR 1,266.69 form
    # would tell EUSA a Finance Team Co-ordinator can sign it, when their own
    # rule sends anything over £1,000 to the Head of Finance — an authorisation
    # control quietly downgraded on a form nobody would think to re-check.
    #
    # Recomputing the cache ourselves would mean reimplementing EUSA's
    # thresholds, which are theirs to change, so the formulas stay the only
    # statement of the rule. Instead:
    #
    #   * fullCalcOnLoad asks for a recalculation. Excel honours it (EUSA's
    #     own tool — the template was authored in Excel Online).
    #   * the cached values are DROPPED, so a reader that ignores the flag has
    #     nothing stale to show. LibreOffice's headless convert is one such
    #     reader, verified.
    #
    # Dropping them degrades the failure to a BLANK authorisation row, which
    # reads as "not filled in" and prompts a human, where a wrong one does not.
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

    # Every refusal here is a form EUSA could not act on. They batch their
    # payment runs, so a wrong form costs a round trip measured in days, while
    # refusing costs the operator a correction before anything is sent.
    def validate!(payment)
      if payment.cost_centre.blank?
        raise TemplateError, "an international payment needs a cost-centre code before the form can be built."
      end

      if payment.amount.nil? || payment.amount.to_d.zero?
        raise TemplateError, "an international payment needs a non-zero amount."
      end

      raise TemplateError, "an international payment needs a BIC/SWIFT code." if payment.bic.blank?

      # The amount label names no currency since EUSA's 2026-09 revision, so a
      # blank here hands them a figure with no unit at all.
      raise TemplateError, "an international payment needs a payment currency." if payment.currency.blank?

      # The last point anything checks the number before EUSA's bank acts on
      # it, and by then the money has moved.
      return if BankDetails.valid_iban?(payment.iban)

      raise TemplateError, "#{payment.iban.presence || 'a blank IBAN'} is not a valid IBAN."
    end

    def write_form(sheet, payment, format_iban:)
      # payee_name and description are submitter-controlled free text landing
      # in a spreadsheet EUSA opens, so they are formula-sanitised exactly as
      # the BACS spreadsheet's are.
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

    # Writes a value while KEEPING the template's styling for that cell.
    # change_contents preserves the style; add_cell would replace the cell and
    # lose it. The template pre-styles every cell we write, so the add_cell
    # fallback is only a guard against a future re-vendoring that drops one.
    def write(sheet, (row, column), value)
      cell = sheet[row] && sheet[row][column]
      return cell.change_contents(value) if cell

      sheet.add_cell(row, column, value)
    end

    # Sterling keeps the template's own "£" format, which is then correct: an
    # international supplier can invoice in GBP. Anything else drops the symbol
    # rather than printing one currency's sign over another's figure.
    def apply_amount_format(sheet, currency)
      return if currency == STERLING

      sheet[CELL_AMOUNT.first][CELL_AMOUNT.last].set_number_format(PLAIN_AMOUNT_FORMAT)
    end

    # A cell pinned to literal text. The template carries leftover
    # sort-code/account-number numeric formats on the BIC and IBAN cells from
    # whichever form it was copied out of; a real BIC or IBAN always contains
    # letters so they are harmless in practice, but the format is corrected
    # rather than relied upon.
    def text(sheet, coordinates, value)
      write(sheet, coordinates, value)
      cell = sheet[coordinates.first][coordinates.last]
      cell.set_number_format(TEXT_FORMAT)
      cell
    end
  end
end
