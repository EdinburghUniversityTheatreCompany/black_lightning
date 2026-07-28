module Reimbursements
  ##
  # The committee's budget spreadsheet, read into buckets an operator confirms
  # before anything is written. Table-less; a pure function of its inputs, so
  # the preview and the apply that follows it can each build one from the same
  # text and be certain they agree.
  #
  # Pasted TSV and uploaded xlsx both come in through ImportParsing, the same
  # concern the membership import uses. An upload is normalised straight to TSV
  # (#to_tsv) and carried through the preview in a hidden field, so the wizard
  # keeps nothing in the session and nothing on disk, and apply re-parses and
  # re-validates from scratch rather than trusting what the preview decided.
  #
  # THE BUCKETS, matched by name within one (financial year, cost centre):
  #
  #   create    a line that matches nothing here yet
  #   revise    an existing line at a different figure — logged as a forecast
  #   unchanged an existing line at the same figure, or with no figure given
  #   invalid   unreadable; blocks the WHOLE import
  #
  # plus #absent_budgets, the lines already in the year that the sheet doesn't
  # mention. They are reported and never touched: a line missing from this
  # month's spreadsheet is nearly always an omission, and deleting a budget
  # would take its claims' history with it.
  #
  # `initial_budget` is written ONLY when a line is created. A re-import logs
  # revisions as forecasts instead, so Budget#variance keeps meaning "drift from
  # the figure the committee agreed" however many times the sheet is re-sent.
  class BudgetImport
    include ImportParsing

    # What a row became, plus everything the preview needs to explain it.
    Entry = Struct.new(:row, :bucket, :budget, :owner_ids, :unknown_owner_emails, :error,
                       keyword_init: true)

    # Canonical headers — what #to_tsv writes and what the downloadable template
    # carries. Reading is more forgiving than this (see the COLUMNS keywords).
    TSV_HEADERS = [ "Budget", "Nominal code", "Type", "Amount", "Owner emails", "Notes" ].freeze

    # Header keywords per field, most specific first, fed to ImportParsing's
    # #find_column (exact match, then "header contains all these words").
    #
    # "budget" is last for the name and absent from the amount on purpose: a
    # sheet whose columns are "Budget" and "Amount" must read the first as the
    # line's name, and one with "Budget name" and "Budget" would otherwise pick
    # the same column for both.
    COLUMNS = {
      name: [ %w[budget\ name], %w[name], %w[line], %w[category], %w[budget] ],
      nominal_code: [ %w[nominal\ code], %w[nominal], %w[code] ],
      budget_type: [ %w[budget\ type], %w[type] ],
      amount: [ %w[amount], %w[initial\ budget], %w[forecast], %w[total] ],
      owner_emails: [ %w[owner\ emails], %w[owner\ email], %w[owners], %w[owner] ],
      notes: [ %w[notes], %w[description], %w[comment] ]
    }.freeze

    # Owner cells hold one or more addresses, separated however the committee
    # felt like separating them.
    OWNER_SEPARATOR = /[,;\s]+/

    attr_reader :entries, :financial_year, :cost_centre

    def initialize(data, input_type:, financial_year:, cost_centre:, existing_budgets: [], people: [])
      @errors = []
      @financial_year = financial_year
      @cost_centre = cost_centre
      @existing_by_name = existing_budgets.index_by { |budget| self.class.match_key(budget.name) }
      @people_by_email = people.index_by { |person| person.email.to_s.strip.downcase }
      @rows = parse_data(data, input_type)
      @entries = categorize
    end

    # Names are matched case- and space-insensitively: a committee retypes
    # "Props" as "props " every other year.
    def self.match_key(name)
      name.to_s.strip.downcase.squeeze(" ")
    end

    # Nothing is written unless every row is readable — a partial import leaves
    # the operator reconciling a half-built year against the spreadsheet by eye.
    def valid?
      @errors.empty? && @entries.any? && @entries.none? { |entry| entry.bucket == :invalid }
    end

    def entries_in(bucket) = @entries.select { |entry| entry.bucket == bucket }

    # Attributes for each new budget, ready for the store.
    def creates
      entries_in(:create).map do |entry|
        { name: entry.row[:name], nominal_code: entry.row[:nominal_code],
          budget_type: entry.row[:budget_type], initial_budget: entry.row[:amount],
          notes: entry.row[:notes], active: true,
          financial_year: financial_year, cost_centre: cost_centre,
          owner_ids: entry.owner_ids }
      end
    end

    # {budget_id:, amount:} per line whose figure has moved — the shape
    # DatabaseStore#create_budget_update! already takes.
    def revisions
      entries_in(:revise).map do |entry|
        { budget_id: entry.budget.record_id, amount: entry.row[:amount] }
      end
    end

    # Owner lists for budgets that already exist. The sheet is the committee's
    # own record of who runs what, so a re-import keeps it current — but only
    # where the sheet actually named someone, since an empty owner column means
    # "not stated", not "nobody".
    def owner_syncs
      (entries_in(:revise) + entries_in(:unchanged)).filter_map do |entry|
        next if entry.owner_ids.empty?
        next if entry.budget.owner_ids.map(&:to_s).sort == entry.owner_ids.sort

        { budget_id: entry.budget.record_id, owner_ids: entry.owner_ids }
      end
    end

    # Lines already in this year that the sheet doesn't mention.
    def absent_budgets
      named = @entries.filter_map { |entry| entry.budget&.record_id }.to_set
      @existing_by_name.values.reject { |budget| named.include?(budget.record_id) }
    end

    def unknown_owner_emails
      @entries.flat_map(&:unknown_owner_emails).uniq
    end

    # Lines with no nominal code — allowed (the overview has a "(none)" bucket
    # for exactly this), but worth saying out loud before it is imported.
    def missing_nominal_codes
      @entries.select { |entry| entry.bucket != :invalid && entry.row[:nominal_code].blank? }
    end

    # The sheet as canonical TSV, for the hidden field that carries an upload
    # from the preview into apply. Tabs and newlines inside a cell are escaped
    # rather than dropped: an xlsx cell really can contain them, and one stray
    # tab would otherwise shift every later column when apply re-parses.
    def to_tsv
      ([ TSV_HEADERS.join("\t") ] + @rows.map { |row| tsv_row(row) }).join("\n")
    end

    private

    def tsv_row(row)
      [ row[:name], row[:nominal_code], row[:budget_type],
        amount_cell(row), Array(row[:owner_emails]).join("; "), row[:notes] ]
        .map { |value| escape_cell(value) }.join("\t")
    end

    # An unreadable amount is carried on VERBATIM. The preview re-renders from
    # this text after a blocked apply, so replacing it with a blank would hide
    # the very cell the operator has to go and fix.
    def amount_cell(row)
      case row[:amount]
      when nil then ""
      when :unreadable then row[:raw_amount].to_s
      else row[:amount].to_s("F")
      end
    end

    ESCAPES = { "\\" => "\\\\", "\t" => "\\t", "\n" => "\\n" }.freeze
    UNESCAPES = { "\\" => "\\", "t" => "\t", "n" => "\n" }.freeze

    # Block-form gsub throughout: the replacement-string form would read a
    # backslash in the replacement as a backreference.
    def escape_cell(value)
      value.to_s.delete("\r").gsub(/[\\\t\n]/) { |char| ESCAPES.fetch(char) }
    end

    def unescape_cell(value)
      value.to_s.gsub(/\\(.)/) { UNESCAPES.fetch(::Regexp.last_match(1), ::Regexp.last_match(0)) }
    end

    # One normalised row per sheet line. Called by ImportParsing's parsers.
    # Returns nil for a wholly blank line so trailing sheet padding is ignored
    # rather than reported as thirty nameless budgets.
    def normalize_row(row)
      return nil if row.values.all?(&:blank?)

      @name_column_present ||= header_for?(row, :name)
      raw_amount = column(row, :amount)
      amount = parse_amount(raw_amount)
      {
        name: unescape_cell(column(row, :name)).strip,
        nominal_code: column(row, :nominal_code).to_s.strip,
        budget_type: normalize_type(column(row, :budget_type)),
        amount: amount,
        # Only kept when it couldn't be read, so the error can quote what was
        # actually typed. Keeping it always would make a row that survived a
        # TSV round-trip ("£1,200" -> "1200.0") differ from the row it came
        # from, for no gain.
        raw_amount: (raw_amount.to_s.strip if amount == :unreadable),
        owner_emails: split_emails(column(row, :owner_emails)),
        notes: unescape_cell(column(row, :notes))
      }
    end

    # Whether the sheet carries a column for +field+ at all, judged on the
    # header alone so an empty cell isn't mistaken for a missing column.
    def header_for?(row, field)
      keywords = COLUMNS.fetch(field).flatten
      row.keys.any? { |key| keywords.any? { |keyword| key.to_s.downcase.include?(keyword) } }
    end

    def column(row, field)
      COLUMNS.fetch(field).each do |keywords|
        value = find_column(row, *keywords)
        return value if value.present?
      end
      nil
    end

    # Blank stays blank ("no figure given"); anything unreadable becomes the
    # :unreadable marker so the row can be flagged by name instead of silently
    # importing as nil — the distinction AmountParser.parse! exists to make.
    def parse_amount(raw)
      AmountParser.parse!(raw)
    rescue AmountParser::Error
      :unreadable
    end

    def normalize_type(raw)
      return "Expense" if raw.blank?

      Budget::TYPES.find { |type| type.casecmp?(raw.to_s.strip) } || raw.to_s.strip
    end

    def split_emails(raw)
      raw.to_s.split(OWNER_SEPARATOR).map { |email| email.strip.downcase }.reject(&:blank?)
    end

    # --- Categorisation ------------------------------------------------------

    def categorize
      return [] if @rows.empty?

      # No name column at all is one problem with the sheet, not thirty broken
      # lines. Judged on the HEADERS, not on the values: a sheet that does have
      # a Budget column but left one cell empty gets that row flagged by itself.
      unless @name_column_present
        @errors << "Couldn't find a budget name column. Name one of the columns " \
                   "#{COLUMNS.fetch(:name).flatten.map(&:inspect).to_sentence(last_word_connector: ' or ')}, " \
                   "or start from the template."
        return []
      end

      duplicated = duplicated_names
      @rows.map { |row| entry_for(row, duplicated) }
    end

    def entry_for(row, duplicated)
      owners, unknown = resolve_owners(row)
      base = { row: row, owner_ids: owners, unknown_owner_emails: unknown }
      error = row_error(row, duplicated)
      return Entry.new(**base, bucket: :invalid, error: error) if error

      budget = @existing_by_name[self.class.match_key(row[:name])]
      Entry.new(**base, budget: budget, bucket: bucket_for(row, budget))
    end

    def bucket_for(row, budget)
      return :create if budget.nil?
      # No figure in the sheet means "leave this line as it is", never zero.
      return :unchanged if row[:amount].nil?

      row[:amount] == budget.projected_amount ? :unchanged : :revise
    end

    def row_error(row, duplicated)
      if row[:name].blank?
        "This line has no budget name, so there's nothing to create or match it against."
      elsif duplicated.include?(self.class.match_key(row[:name]))
        "#{row[:name].inspect} appears more than once in this sheet — a budget name has to be " \
          "unique within a year, so it isn't clear which figure is meant."
      elsif row[:amount] == :unreadable
        "#{row[:raw_amount].inspect} isn't an amount. Leave it blank to keep the current figure."
      elsif Budget::TYPES.exclude?(row[:budget_type])
        "#{row[:budget_type].inspect} isn't a budget type. Use #{Budget::TYPES.to_sentence(last_word_connector: ' or ')}."
      end
    end

    def duplicated_names
      @rows.map { |row| self.class.match_key(row[:name]) }.reject(&:blank?)
           .tally.select { |_name, count| count > 1 }.keys.to_set
    end

    # People for the sheet's owner emails, plus the addresses that matched
    # nobody. Never creates a Person: a bare email would land as a person named
    # by their address, and duplicate People are exactly what the email unique
    # index exists to stop.
    def resolve_owners(row)
      found = []
      unknown = []
      Array(row[:owner_emails]).each do |email|
        person = @people_by_email[email]
        person ? found << person.id.to_s : unknown << email
      end
      [ found, unknown ]
    end
  end
end
