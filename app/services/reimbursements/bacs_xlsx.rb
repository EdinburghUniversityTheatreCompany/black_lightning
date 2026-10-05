module Reimbursements
  ##
  # Fills EUSA's BACS request template (its BREAKDOWN sheet) with one row per
  # expense and returns the workbook bytes. Sort code, account number and
  # nominal code are forced to TEXT so leading zeros and dashes survive.
  class BacsXlsx
    # Bank-detail fields stay strings to keep leading zeros; +amount+ is numeric.
    BacsRow = Struct.new(:payee_name, :amount, :sort_code, :account_number,
                         :nominal_code, :description, :payment_reference, :cost_centre,
                         keyword_init: true)

    SHEET_NAME = "BREAKDOWN".freeze
    # 0-based, below the template's header and example rows.
    DATA_START_ROW = 2
    # The GRAND TOTAL row's SUM (and the Authorisation Form's total) covers
    # exactly this many rows, so a bigger batch would fall off the total or
    # overwrite it. Split it into several submissions.
    MAX_ROWS = 200
    # Columns match the EUSA template, 0-based.
    COL_PAYEE = 0
    COL_AMOUNT = 1
    COL_SORT_CODE = 2
    COL_ACCOUNT_NUMBER = 3
    COL_NOMINAL_CODE = 4
    COL_COST_CENTRE = 5
    COL_PAYMENT_REFERENCE = 6
    COL_DESCRIPTION = 7
    # Excel's builtin text number format.
    TEXT_FORMAT = "@".freeze

    DEFAULT_TEMPLATE_PATH =
      Rails.root.join("lib/reimbursements/templates/EUSA_BACS_template.xlsx").freeze

    class TemplateError < StandardError; end

    def initialize(template_path: DEFAULT_TEMPLATE_PATH)
      @template_path = Pathname(template_path)
      return if @template_path.exist?

      raise TemplateError, "BACS template not found at #{@template_path}"
    end

    # Re-reads the template on every call, so one instance builds many workbooks.
    def generate(rows)
      # Not at file scope: eager loading would pull rubyXL into every process.
      require "rubyXL"
      require "rubyXL/convenience_methods"

      if rows.size > MAX_ROWS
        raise TemplateError,
              "#{rows.size} expenses exceed the BACS template's #{MAX_ROWS}-row capacity. " \
              "split this into multiple submissions."
      end

      # Refuse rather than default: a termtime row stamped F40 is paid from the
      # Fringe's pot.
      if rows.any? { |row| row.cost_centre.blank? }
        raise TemplateError, "every BACS row needs a cost-centre code before the spreadsheet can be built."
      end

      workbook = RubyXL::Parser.parse(@template_path.to_s)
      sheet = workbook[SHEET_NAME]
      unless sheet
        raise TemplateError,
              "template has no '#{SHEET_NAME}' sheet (found: #{workbook.worksheets.map(&:sheet_name).inspect})"
      end

      rows.each_with_index do |row, index|
        write_row(sheet, DATA_START_ROW + index, row)
      end

      workbook.stream.string
    end

    private

    def write_row(sheet, row_index, row)
      # Every text cell is formula-sanitised, the bank and nominal cells too as
      # defence in depth (nominal_code_override has no format validation).
      sheet.add_cell(row_index, COL_PAYEE, sanitize(row.payee_name))
      sheet.add_cell(row_index, COL_AMOUNT, row.amount.to_f)
      text_cell(sheet, row_index, COL_SORT_CODE, row.sort_code)
      text_cell(sheet, row_index, COL_ACCOUNT_NUMBER, row.account_number)
      text_cell(sheet, row_index, COL_NOMINAL_CODE, row.nominal_code)
      sheet.add_cell(row_index, COL_COST_CENTRE, row.cost_centre)
      sheet.add_cell(row_index, COL_PAYMENT_REFERENCE, sanitize(row.payment_reference))
      sheet.add_cell(row_index, COL_DESCRIPTION, sanitize(row.description))
    end

    def sanitize(value)
      CellSanitizer.sanitize(value)
    end

    def text_cell(sheet, row_index, column_index, value)
      cell = sheet.add_cell(row_index, column_index, sanitize(value))
      cell.set_number_format(TEXT_FORMAT)
      cell
    end
  end
end
