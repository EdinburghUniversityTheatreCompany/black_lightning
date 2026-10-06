module Reimbursements
  ##
  # Turns an uploaded actuals export into the tab-separated text the reconcile wizard parses.
  # Reconcile is stateless (preview and apply re-parse a hidden field), so a file is converted once
  # on the way in and everything downstream runs on exactly what a paste produces: this adds a
  # reader, not a second pipeline.
  class ActualsUpload
    ACCEPT = ".xlsx,.csv,.txt,.tsv".freeze

    # The OLE2 signature of a legacy .xls. Checked as well as the extension, because a renamed .xls
    # reaches rubyzip instead.
    LEGACY_SPREADSHEET_MAGIC = "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b.freeze

    LEGACY_SPREADSHEET_ADVICE = "this reads .xlsx, not the older .xls. Open it in Excel and " \
                                "choose Save As .xlsx, or paste the rows instead.".freeze

    # Appended where the cause is unknown. Every message raised here carries a next step exactly
    # once, so callers must not add their own.
    GENERIC_ADVICE = "Save it as .xlsx or .csv, or paste the rows instead.".freeze

    # Not the format advice: the file read fine, its first sheet is empty (the wrong tab exported).
    EMPTY_SHEET_ADVICE = "that sheet is empty. Check the rows are in the file's first sheet, " \
                         "or paste them instead.".freeze

    # So the controller reports an unreadable file on the form instead of 500ing.
    class UnreadableError < StandardError; end

    class << self
      def to_text(file)
        name = file.original_filename.to_s
        extension = File.extname(name).downcase
        raise UnreadableError, LEGACY_SPREADSHEET_ADVICE if legacy_spreadsheet?(file, extension)

        if extension == ".xlsx"
          spreadsheet_to_tsv(file)
        else
          # parse_actuals_rows detects the separator itself.
          file.read.to_s.force_encoding(Encoding::UTF_8).scrub
        end
      rescue UnreadableError
        raise
      rescue StandardError => e
        raise UnreadableError, "#{e.message.to_s.sub(/\.\z/, '')}. #{GENERIC_ADVICE}"
      end

      private

      def legacy_spreadsheet?(file, extension)
        # roo 3 dropped .xls and we do not carry roo-xls, so one reaching Roo surfaces its internals
        # to the operator. EUSA's exports are .xlsx; add roo-xls if that stops being true.
        return true if extension == ".xls"

        head = file.read(LEGACY_SPREADSHEET_MAGIC.bytesize)
        file.rewind
        head == LEGACY_SPREADSHEET_MAGIC
      end

      def spreadsheet_to_tsv(file)
        require "roo" # lazy: kept out of the boot heap (Gemfile require: false)
        sheet = Roo::Spreadsheet.open(file.path, extension: :xlsx).sheet(0)
        raise UnreadableError, EMPTY_SHEET_ADVICE if sheet.last_row.nil?

        (1..sheet.last_row).filter_map { |i| tsv_line(sheet.row(i)) }.join("\n")
      end

      # A cell's own tabs and newlines become spaces, or a Sage narrative containing one would split
      # into two columns and silently shift every figure on the row.
      def tsv_line(values)
        return nil if values.all?(&:blank?)

        values.map { |value| value.to_s.gsub(/[\t\r\n]+/, " ").strip }.join("\t")
      end
    end
  end
end
