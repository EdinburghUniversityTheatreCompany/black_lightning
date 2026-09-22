module Reimbursements
  ##
  # Turns an uploaded actuals export into the TAB-SEPARATED TEXT the reconcile
  # wizard already parses.
  #
  # Reconcile is stateless: preview and apply both re-parse the text carried in
  # a hidden field, and an upload has no second file to re-send. So a file is
  # converted to text ONCE, on the way in, and everything downstream —
  # Reconciliation.parse_actuals_rows, the legacy/Sage auto-detect, the matcher,
  # the offsetting-pair detection — runs on exactly what a paste produces. That
  # is the whole point: the upload path adds a reader, not a second pipeline
  # whose results could differ from the pasted one's.
  class ActualsUpload
    # What the file picker accepts, and what this can read.
    ACCEPT = ".xlsx,.csv,.txt,.tsv".freeze

    SPREADSHEET_EXTENSIONS = %w[.xlsx].freeze

    # roo 3 dropped legacy .xls and we do not carry roo-xls, so one reaching
    # Roo surfaces its internals to a finance operator. EUSA's exports are
    # .xlsx; add roo-xls if that stops being true.
    LEGACY_SPREADSHEET_EXTENSIONS = %w[.xls].freeze

    # The OLE2 signature a legacy .xls opens with. Checked as well as the
    # extension: the picker offers only .xlsx now, so an operator holding an
    # old file renames it, and a renamed one reaches rubyzip instead.
    LEGACY_SPREADSHEET_MAGIC = "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b.freeze

    LEGACY_SPREADSHEET_ADVICE = "this reads .xlsx, not the older .xls. Open it in Excel and " \
                                "choose Save As .xlsx, or paste the rows instead.".freeze

    # Appended where the cause is not known. Every message raised here carries
    # a next step exactly once, so callers must not add their own.
    GENERIC_ADVICE = "Save it as .xlsx or .csv, or paste the rows instead.".freeze

    # The format advice would be wrong here: the file read fine, it is the
    # FIRST sheet that has no rows, which is what an export of the wrong tab
    # looks like.
    EMPTY_SHEET_ADVICE = "that sheet is empty. Check the rows are in the file's first sheet, " \
                         "or paste them instead.".freeze

    # Raised for a file this cannot read, so the controller reports it on the
    # form rather than 500ing with the operator's upload lost.
    class UnreadableError < StandardError; end

    class << self
      def to_text(file)
        name = file.original_filename.to_s
        extension = File.extname(name).downcase
        raise UnreadableError, LEGACY_SPREADSHEET_ADVICE if legacy_spreadsheet?(file, extension)

        if SPREADSHEET_EXTENSIONS.include?(extension)
          spreadsheet_to_tsv(file)
        else
          # A .csv or .tsv is already the text the parser reads, and
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
        return true if LEGACY_SPREADSHEET_EXTENSIONS.include?(extension)

        head = file.read(LEGACY_SPREADSHEET_MAGIC.bytesize)
        file.rewind
        head == LEGACY_SPREADSHEET_MAGIC
      end

      def spreadsheet_to_tsv(file)
        require "roo" # lazy: kept out of the boot heap (Gemfile require: false)
        sheet = Roo::Spreadsheet.open(file.path, extension: File.extname(file.original_filename.to_s).delete("."))
                                .sheet(0)
        raise UnreadableError, EMPTY_SHEET_ADVICE if sheet.last_row.nil?

        (1..sheet.last_row).filter_map { |i| tsv_line(sheet.row(i)) }.join("\n")
      end

      # One spreadsheet row as a tab-separated line, or nil for a blank one.
      #
      # A cell's own tabs and newlines become spaces: they cannot survive in a
      # tab-separated line, and a Sage narrative that happens to contain one
      # would otherwise split into two columns and shift every figure on the
      # row one place left — silently, into the wrong column.
      def tsv_line(values)
        return nil if values.all?(&:blank?)

        values.map { |value| value.to_s.gsub(/[\t\r\n]+/, " ").strip }.join("\t")
      end
    end
  end
end
