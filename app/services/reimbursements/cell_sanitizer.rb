module Reimbursements
  ##
  # The one spreadsheet-cell formula-injection guard for the whole
  # reimbursements section: the BACS xlsx (BacsXlsx), every per-view CSV and
  # the combined workbook (Exports::*) all route submitter-controlled text
  # through here, so the rule can never drift between them.
  #
  # A cell whose text begins with "=", "+", "-", "@" or a tab/CR/LF is treated
  # as a formula by Excel, Sheets and Numbers — including on CSV *re-import*,
  # which is exactly what finance does with these exports. Prefixing a single
  # quote makes the value render as literal text instead of executing.
  module CellSanitizer
    # Leading characters that make a spreadsheet treat a text cell as a formula.
    FORMULA_TRIGGERS = [ "=", "+", "-", "@", "\t", "\r", "\n" ].freeze

    module_function

    # String in, string out: the guard for a cell that is always text (the BACS
    # template's payee/reference/description and its text-formatted bank
    # fields). Ordinary and empty values pass through unchanged.
    def sanitize(value)
      text = value.to_s
      return text unless text.start_with?(*FORMULA_TRIGGERS)

      "'#{text}"
    end

    # Type-preserving guard for the mixed-type rows the exporters build: only
    # *text* can carry an injected formula, and stringifying anything else
    # would corrupt it — a negative amount (-12.50) or a negative variance is a
    # number, not an attack, and quoting it would land a text cell in the
    # spreadsheet that no longer sums. So numbers, dates, booleans and nil pass
    # through untouched and only Strings are guarded.
    def cell(value)
      value.is_a?(String) ? sanitize(value) : value
    end
  end
end
