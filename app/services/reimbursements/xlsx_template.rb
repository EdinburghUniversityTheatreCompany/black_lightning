module Reimbursements
  ##
  # What BacsXlsx and InternationalXlsx share: a vendored EUSA template, re-read
  # on every call so one instance builds many files. An includer defines
  # DEFAULT_TEMPLATE_PATH, TEMPLATE_LABEL (for the missing-file message) and
  # SHEET_NAME.
  module XlsxTemplate
    class TemplateError < StandardError; end

    # Excel's builtin text number format.
    TEXT_FORMAT = "@".freeze

    def initialize(template_path: self.class::DEFAULT_TEMPLATE_PATH)
      @template_path = Pathname(template_path)
      return if @template_path.exist?

      raise TemplateError, "#{self.class::TEMPLATE_LABEL} not found at #{@template_path}"
    end

    private

    # Returns [workbook, the includer's sheet].
    def open_workbook
      # Not at file scope: eager loading would pull rubyXL into every process.
      require "rubyXL"
      require "rubyXL/convenience_methods"

      workbook = RubyXL::Parser.parse(@template_path.to_s)
      sheet = workbook[self.class::SHEET_NAME]
      return [ workbook, sheet ] if sheet

      raise TemplateError,
            "template has no '#{self.class::SHEET_NAME}' sheet (found: #{workbook.worksheets.map(&:sheet_name).inspect})"
    end

    # change_contents keeps the template's style; add_cell would drop it. The
    # fallback only guards against a re-vendored template missing a cell.
    # Returns the cell.
    def write(sheet, row, column, value)
      cell = sheet[row] && sheet[row][column]
      return sheet.add_cell(row, column, value) unless cell

      cell.change_contents(value)
      cell
    end

    # Pinned to text, over whatever number format the template left on the cell
    # (the BIC and IBAN cells carry sort-code and account-number formats).
    def write_text(sheet, row, column, value)
      write(sheet, row, column, value).tap { |cell| cell.set_number_format(TEXT_FORMAT) }
    end
  end
end
