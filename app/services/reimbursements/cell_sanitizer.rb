module Reimbursements
  ##
  # The one spreadsheet formula-injection guard for the section: BacsXlsx, every
  # per-view CSV and the combined workbook route submitter-controlled text
  # through here, so the rule cannot drift between them.
  #
  # Text starting "=", "+", "-", "@" or tab/CR/LF executes as a formula in
  # Excel, Sheets and Numbers, including on CSV re-import, which finance does.
  # A leading single quote makes it literal text.
  module CellSanitizer
    FORMULA_TRIGGERS = [ "=", "+", "-", "@", "\t", "\r", "\n" ].freeze

    module_function

    # String in, string out, for a cell that is always text (the BACS template's).
    def sanitize(value)
      text = value.to_s
      return text unless text.start_with?(*FORMULA_TRIGGERS)

      "'#{text}"
    end

    # Type-preserving, for the exporters' mixed rows: only Strings are guarded.
    # A negative amount is a number, not an attack, and quoting it would land a
    # text cell that no longer sums.
    def cell(value)
      value.is_a?(String) ? sanitize(value) : value
    end
  end
end
