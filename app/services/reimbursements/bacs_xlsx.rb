module Reimbursements
  ##
  # Fills EUSA's BACS request template (its BREAKDOWN sheet) with one row per
  # expense and returns the workbook bytes. Sort code, account number and
  # nominal code are forced to TEXT so leading zeros and dashes survive.
  class BacsXlsx
    include XlsxTemplate

    # Bank-detail fields stay strings to keep leading zeros; +amount+ is numeric.
    BacsRow = Struct.new(:payee_name, :amount, :sort_code, :account_number,
                         :nominal_code, :description, :payment_reference, :cost_centre,
                         keyword_init: true)

    SHEET_NAME = "BREAKDOWN".freeze
    TEMPLATE_LABEL = "BACS template".freeze
    AUTHORISATION_SHEET_NAME = "AUTHORISATION FORM".freeze
    # 0-based [row, column]: D4, C16, C17.
    CENTRE_NAME_CELL = [ 3, 3 ].freeze
    AUTHORISER_NAME_CELL = [ 15, 2 ].freeze
    AUTHORISER_DESIGNATION_CELL = [ 16, 2 ].freeze
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

    DEFAULT_TEMPLATE_PATH =
      Rails.root.join("lib/reimbursements/templates/EUSA_BACS_template.xlsx").freeze

    # Re-reads the template on every call, so one instance builds many workbooks.
    def generate(rows, centre_name: nil, authoriser_name: nil, authoriser_designation: nil)
      if rows.size > MAX_ROWS
        raise TemplateError,
              "#{rows.size} expenses exceed the BACS template's #{MAX_ROWS}-row capacity. " \
              "split this into multiple submissions."
      end

      workbook, sheet = open_workbook
      rows.each_with_index do |row, index|
        write_row(sheet, DATA_START_ROW + index, row)
      end

      authorisation = workbook[AUTHORISATION_SHEET_NAME]
      write(authorisation, *CENTRE_NAME_CELL, CellSanitizer.sanitize(centre_name))
      write(authorisation, *AUTHORISER_NAME_CELL, CellSanitizer.sanitize(authoriser_name))
      write(authorisation, *AUTHORISER_DESIGNATION_CELL, CellSanitizer.sanitize(authoriser_designation))

      workbook.stream.string
    end

    private

    def write_row(sheet, row_index, row)
      # Every text cell is formula-sanitised, the bank and nominal cells too as
      # defence in depth (nominal_code_override has no format validation).
      write(sheet, row_index, COL_PAYEE, CellSanitizer.sanitize(row.payee_name))
      write(sheet, row_index, COL_AMOUNT, row.amount.to_f)
      write_text(sheet, row_index, COL_SORT_CODE, CellSanitizer.sanitize(row.sort_code))
      write_text(sheet, row_index, COL_ACCOUNT_NUMBER, CellSanitizer.sanitize(row.account_number))
      write_text(sheet, row_index, COL_NOMINAL_CODE, CellSanitizer.sanitize(row.nominal_code))
      write(sheet, row_index, COL_COST_CENTRE, row.cost_centre)
      write(sheet, row_index, COL_PAYMENT_REFERENCE, CellSanitizer.sanitize(row.payment_reference))
      write(sheet, row_index, COL_DESCRIPTION, CellSanitizer.sanitize(row.description))
    end
  end
end
