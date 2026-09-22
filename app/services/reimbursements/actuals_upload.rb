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

    # roo 3 dropped legacy .xls and we do not carry roo-xls, so one reached
    # Roo and came back "Can't detect the type of /tmp/actuals…xls - please use
    # the :extension option to declare its type" — a tmp path and a
    # developer's instruction, shown to a finance operator. Named here so the
    # refusal says what to do instead. EUSA's exports are .xlsx; add roo-xls if
    # that ever stops being true.
    LEGACY_SPREADSHEET_EXTENSIONS = %w[.xls].freeze

    # Raised for a file this cannot read, so the controller reports it on the
    # form rather than 500ing with the operator's upload lost.
    class UnreadableError < StandardError; end

    class << self
      def to_text(file)
        name = file.original_filename.to_s
        extension = File.extname(name).downcase
        if LEGACY_SPREADSHEET_EXTENSIONS.include?(extension)
          raise UnreadableError, "this reads .xlsx, not the older .xls. Open it in Excel and " \
                                 "choose Save As .xlsx, or paste the rows instead"
        end

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
        raise UnreadableError, e.message
      end

      private

      def spreadsheet_to_tsv(file)
        require "roo" # lazy: kept out of the boot heap (Gemfile require: false)
        sheet = Roo::Spreadsheet.open(file.path, extension: File.extname(file.original_filename.to_s).delete("."))
                                .sheet(0)
        raise UnreadableError, "that sheet is empty" if sheet.last_row.nil?

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
