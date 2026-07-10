require "rubyXL"
require "rubyXL/convenience_methods"

module Reimbursements
  ##
  # Fills the vendored EUSA BACS request template in place (preserving EUSA's
  # exact cell styling) with one row per expense, and returns the workbook bytes.
  # Ported from bedlam-bacs `xlsx_generator.py`, swapping openpyxl for rubyXL.
  #
  # The template's BREAKDOWN sheet has a header in row 1 and an F40 example in
  # row 2; data is written from row 3 (0-based index 2). Sort code, account
  # number and nominal code are forced to TEXT format ("@") so leading zeros and
  # dashes survive — the whole reason we don't build the sheet from scratch.
  class BacsXlsx
    # One row destined for the BACS spreadsheet. Bank-detail fields stay strings
    # to preserve leading zeros; +amount+ is numeric (the template's currency
    # format applies). Mirrors bedlam-bacs' BacsRow.
    BacsRow = Struct.new(:payee_name, :amount, :sort_code, :account_number,
                         :nominal_code, :description, :payment_reference, :cost_centre,
                         keyword_init: true)

    SHEET_NAME = "BREAKDOWN".freeze
    # 0-based: rows 0 (header) and 1 (example) are reserved by the template.
    DATA_START_ROW = 2
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

    # Render the spreadsheet as bytes, suitable for attaching to an email or
    # uploading to SharePoint. The template is re-read on every call so one
    # instance can produce many workbooks without state bleed.
    def generate(rows)
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
      sheet.add_cell(row_index, COL_PAYEE, row.payee_name.to_s)
      # rubyXL serialises a Float cleanly; the template's currency format renders it.
      sheet.add_cell(row_index, COL_AMOUNT, row.amount.to_f)
      text_cell(sheet, row_index, COL_SORT_CODE, row.sort_code)
      text_cell(sheet, row_index, COL_ACCOUNT_NUMBER, row.account_number)
      text_cell(sheet, row_index, COL_NOMINAL_CODE, row.nominal_code)
      sheet.add_cell(row_index, COL_COST_CENTRE, row.cost_centre.presence || "F40")
      sheet.add_cell(row_index, COL_PAYMENT_REFERENCE, row.payment_reference.to_s)
      sheet.add_cell(row_index, COL_DESCRIPTION, row.description.to_s)
    end

    # A cell written as literal text so leading zeros / dashes are preserved.
    def text_cell(sheet, row_index, column_index, value)
      cell = sheet.add_cell(row_index, column_index, value.to_s)
      cell.set_number_format(TEXT_FORMAT)
      cell
    end
  end
end
