module Reimbursements
  ##
  # The strict header matcher shared by BudgetImport and ExpenseImport: EXACT
  # names first, then MULTI-WORD phrases only. A bare-word substring match read
  # an "Account number" column as ExpenseImport's expense number and numbered
  # every later claim from 66,374,959. ImportParsing#find_column keeps the
  # looser fallback for the flatter membership and user sheets.
  #
  # The includer defines FIELDS (field => { label:, exact: [...], contains: [...] },
  # each entry already normalised by #normalize_header), TSV_HEADERS, #cell_for(row,
  # field), and @rows and @errors (Arrays); it includes ImportParsing for #escape_cell
  # and calls #resolve_headers as its rows arrive. FIELDS and TSV_HEADERS are read
  # through self.class, since a bare constant here would resolve to this module's scope.
  module StrictColumnMatching
    extend ActiveSupport::Concern

    # Canonical heading => the sheet's own heading it was read from (nil when absent).
    # The preview prints it, so a mis-mapping is visible: keyword matching can only be
    # nearly right.
    def column_mapping
      self.class::FIELDS.to_h { |field, spec| [ spec[:label], header_for[field] ] }
    end

    # The sheet as canonical TSV, carrying an upload through the preview's hidden field.
    # Tabs and newlines in a cell are escaped, not dropped: an xlsx cell can hold them,
    # and one stray tab would shift every later column when apply re-parses.
    def to_tsv
      ([ self.class::TSV_HEADERS.join("\t") ] + @rows.map { |row| tsv_row(row) }).join("\n")
    end

    private

    # "E-mail", "e mail" and "EMAIL" are one name.
    def normalize_header(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    def match_header(headers, spec)
      spec[:exact].each do |name|
        found = headers.find { |header| normalize_header(header) == name }
        return found if found
      end
      spec[:contains].each do |phrase|
        found = headers.find { |header| normalize_header(header).include?(phrase) }
        return found if found
      end
      nil
    end

    def header_for
      @header_for ||= {}
    end

    def tsv_row(row)
      self.class::FIELDS.each_key.map { |field| escape_cell(cell_for(row, field)) }.join("\t")
    end

    def resolve_headers(headers)
      self.class::FIELDS.transform_values { |spec| match_header(headers, spec) }
    end

    # Refused rather than resolved: a guess writes a wrong value into a name, a figure or
    # an identity with nothing on screen to say so.
    def ambiguous_columns
      header_for.compact.group_by { |_field, header| header }
                .select { |_header, pairs| pairs.size > 1 }
    end

    def report_ambiguous_columns
      ambiguous_columns.each do |header, pairs|
        labels = pairs.map { |field, _| self.class::FIELDS.fetch(field)[:label] }
        @errors << "The column #{header.inspect} would be read as both " \
                   "#{labels.to_sentence(last_word_connector: ' and ')}. Rename one of them, " \
                   "or start from the template."
      end
    end

    # Blank stays nil ("no figure given"); anything unreadable becomes :unreadable so the
    # row is flagged rather than imported as nil.
    def parse_amount(raw)
      AmountParser.parse!(raw)
    rescue AmountParser::Error
      :unreadable
    end
  end
end
