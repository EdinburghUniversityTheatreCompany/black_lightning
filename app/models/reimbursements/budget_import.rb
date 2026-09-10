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
    include StrictColumnMatching

    # What a row became, plus everything the preview needs to explain it.
    Entry = Struct.new(:row, :bucket, :budget, :owner_ids, :unknown_owner_emails, :error,
                       :area_name, keyword_init: true)

    # One entry per column, in the order #to_tsv writes them: +label+ is the
    # canonical heading, +exact+ matches a header WHOLE, +contains+ matches a
    # substring and is multi-word only (see the class note below).
    #
    # A heading not listed here is simply not found, which reads as "the sheet
    # has no X column" for the required field and a blank for an optional one —
    # the safe direction, since a column read as the WRONG field is silent
    # while one not read at all is stated.
    #
    # **Columns are matched here, NOT through ImportParsing#find_column**, whose
    # "any header containing the keyword" fallback is the class of bug
    # ExpenseImport was fixed for in September 2026: "budget" is a bare
    # single-word keyword for +name+, so once a header like "Area Budget"
    # exists on the sheet (Phase 2b), a bare-keyword fallback could read it as
    # the line's own name. So: EXACT names first, then MULTI-WORD phrases
    # only — a bare word is never a substring hint — and two fields resolving
    # to one column is a blocking error naming both, rather than a silent pick.
    FIELDS = {
      area: {
        label: "Area",
        exact: [ "area" ],
        # NOT "area": a bare word is never a substring hint (see the class
        # note above). Task 3's "Area Budget" header contains this phrase, and
        # matching it here would read that column as the area name too.
        contains: [ "area name" ]
      },
      area_budget: {
        label: "Area Budget",
        # Both multi-word, so neither collides with the bare "area" (the name
        # column above) or "budget" (the line-name column below) — the same
        # rule that keeps "area name" out of THIS field's own contains list.
        exact: [ "area budget", "area total" ],
        contains: [ "area budget", "area total" ]
      },
      name: {
        label: "Budget",
        exact: [ "budget name", "name", "line", "category", "budget" ],
        contains: [ "budget name" ]
      },
      nominal_code: {
        label: "Nominal code",
        exact: [ "nominal code", "nominal", "code" ],
        contains: [ "nominal code" ]
      },
      budget_type: {
        label: "Type",
        exact: [ "budget type", "type" ],
        contains: [ "budget type" ]
      },
      amount: {
        label: "Amount",
        exact: [ "amount", "initial budget", "forecast", "total" ],
        contains: [ "initial budget" ]
      },
      owner_emails: {
        label: "Owner emails",
        exact: [ "owner emails", "owner email", "owners", "owner" ],
        contains: [ "owner emails", "owner email" ]
      },
      notes: {
        label: "Notes",
        exact: [ "notes", "description", "comment" ],
        contains: []
      }
    }.freeze

    # Canonical headers — what #to_tsv writes and what the downloadable
    # template carries. Reading is more forgiving than this (see FIELDS).
    TSV_HEADERS = FIELDS.each_value.map { |spec| spec[:label] }.freeze

    # The only column a sheet must carry — nominal code, type, amount and
    # owners can all be blank or defaulted, but a line with no name has
    # nothing to create or match against.
    REQUIRED_FIELDS = %i[name].freeze

    # Owner cells hold one or more addresses, separated however the committee
    # felt like separating them.
    OWNER_SEPARATOR = /[,;\s]+/

    # Fields whose cells may hold a tab or a newline, so must be unescaped when
    # the text came back from #to_tsv. See @escaped below.
    TEXT_FIELDS = %i[name notes area].freeze

    attr_reader :entries, :financial_year, :cost_centre

    # +input_type+ is :paste (the operator's own text), :xlsx (an upload), or
    # :canonical_tsv — this class's own #to_tsv output coming back from the
    # preview's hidden field, which is the ONLY input whose cells carry escape
    # sequences. Unescaping the operator's paste instead rewrote a typed
    # "C:\temp\report.pdf" with a real tab before storing it — and before
    # matching it against an existing budget's name.
    def initialize(data, input_type:, financial_year:, cost_centre:, existing_budgets: [],
                  existing_areas: [], people: [])
      @errors = []
      @financial_year = financial_year
      @cost_centre = cost_centre
      @escaped = input_type == :canonical_tsv
      @existing_by_name = existing_budgets.index_by { |budget| self.class.match_key(budget.name) }
      @existing_areas_by_name = existing_areas.index_by { |area| self.class.match_key(area.name) }
      @people_by_email = people.index_by { |person| person.email.to_s.strip.downcase }
      @rows = parse_data(data, @escaped ? :paste : input_type)
      @entries = categorize
      report_area_total_conflicts
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

    # Attributes for each new budget, ready for the store. A line naming an
    # AREA carries either +area_id:+ (an area already in this year/centre) or
    # +area_name:+ (one the sheet is about to create) — never both, and
    # neither when the Area column was left blank. import_budgets! resolves
    # +area_name:+ to an id once #area_creates has run, inside its transaction.
    def creates
      entries_in(:create).map do |entry|
        { name: entry.row[:name], nominal_code: entry.row[:nominal_code],
          budget_type: entry.row[:budget_type], initial_budget: entry.row[:amount],
          notes: entry.row[:notes], active: true,
          financial_year: financial_year, cost_centre: cost_centre,
          owner_ids: entry.owner_ids }.merge(area_attrs_for(entry))
      end
    end

    # {name:, cost_centre:, financial_year:, initial_budget:} for every area
    # the sheet names that doesn't already exist here — matched the same way a
    # budget line is matched (by name within one financial year and cost
    # centre), and never deleted for the same reason #absent_budgets is
    # reported and never touched: a show's claims and history hang off its
    # lines.
    #
    # Reads every entry the sheet actually kept (create/revise/unchanged), not
    # only #creates: an area can be named on a line that matches an EXISTING
    # budget too, and a typo on an :invalid row must not mint a spurious area
    # while the whole import is blocked anyway.
    #
    # +initial_budget+ is written ONLY here, on create — an area that already
    # exists (excluded above) keeps its own figure, the same write-once rule
    # Budget#initial_budget follows. #area_total_conflicts is what stops two
    # different Area Budget cells for the same area picking one arbitrarily.
    def area_creates
      totals = area_budget_totals
      first_seen_names.except(*@existing_areas_by_name.keys).map do |key, name|
        { name: name, cost_centre: cost_centre, financial_year: financial_year,
          initial_budget: totals[key]&.first }
      end
    end

    # [{ area_name:, values: [] }] for every area the sheet gives more than one
    # distinct, non-blank Area Budget figure — the column repeats down every
    # row of the area, so two different values within one sheet can't both be
    # what the committee agreed. #valid? refuses the whole import over this,
    # the same way an unreadable Amount does, rather than picking one.
    def area_total_conflicts
      area_budget_totals.filter_map do |key, values|
        next if values.size <= 1

        { area_name: first_seen_names[key], values: values }
      end
    end

    # {budget_id:, amount:} per line whose figure has moved — the shape
    # DatabaseStore#create_budget_update! already takes.
    def revisions
      entries_in(:revise).map do |entry|
        { budget_id: entry.budget.record_id, amount: entry.row[:amount] }
      end
    end

    # Matched budgets that belong to no cost centre yet — this import ADOPTS
    # them into the one it is being run for.
    #
    # The lenient scoping that lets a legacy unplaced line be MATCHED at all
    # (DatabaseStore#in_cost_centre) also puts it in every centre's list, so
    # without adoption two committees' sheets would take turns revising the same
    # "Venue hire" row, each overwriting the other's forecast, and neither
    # centre would ever get a line of its own — while Budget#variance quietly
    # measured drift against a figure nobody agreed. Adopting on the first
    # import claims the row (keeping its claims and its forecast history, which
    # creating a fresh line beside it would strand), and the second centre no
    # longer matches it, so it creates its own.
    #
    # Same shape and same buckets as #owner_syncs: a matched line is matched
    # whether or not its figure moved, so this must not depend on :revise alone.
    def adoptions
      return [] if cost_centre.nil?

      (entries_in(:revise) + entries_in(:unchanged)).filter_map do |entry|
        next if entry.budget.cost_centre_id

        { budget_id: entry.budget.record_id, cost_centre: cost_centre }
      end
    end

    # Owner lists for budgets that already exist. The sheet is the committee's
    # own record of who runs what, so a re-import keeps it current — but only
    # where the sheet actually named someone, since an empty owner column means
    # "not stated", not "nobody".
    #
    # Compared against the budget's OWN owner rows, because that is what
    # DatabaseStore#sync_budget_owners! writes. Budget#owner_ids resolves
    # through the area when there is one, so comparing it could never
    # converge: the apply would write the sheet's owner into own_owners,
    # #owners would keep returning the area's, and every later re-import
    # would report the identical sync for ever. Whether the sheet's owner
    # column should instead target the AREA for a line that has one is a
    # separate (Phase 2) question — this only makes the comparison agree with
    # the write.
    def owner_syncs
      (entries_in(:revise) + entries_in(:unchanged)).filter_map do |entry|
        next if entry.owner_ids.empty?
        next if entry.budget.own_owners.map(&:record_id).sort == entry.owner_ids.map(&:to_s).sort

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

    # Canonical heading => the sheet's own heading it was read from (nil when
    # the sheet has no such column). Rendered by the preview: keyword matching
    # can only ever be nearly right, and stating what was read is worth more
    # than any amount of tuning.
    def column_mapping
      FIELDS.to_h { |field, spec| [ spec[:label], header_for[field] ] }
    end

    private

    def header_for
      @header_for ||= {}
    end

    def tsv_row(row)
      FIELDS.each_key.map { |field| escape_cell(cell_for(row, field)) }.join("\t")
    end

    # An unreadable amount is carried on VERBATIM. The preview re-renders from
    # this text after a blocked apply, so replacing it with a blank would hide
    # the very cell the operator has to go and fix.
    def cell_for(row, field)
      case field
      when :amount
        case row[:amount]
        when nil then ""
        when :unreadable then row[:raw_amount].to_s
        else row[:amount].to_s("F")
        end
      when :area_budget
        row[:area_budget].nil? ? "" : row[:area_budget].to_s("F")
      when :owner_emails
        Array(row[:owner_emails]).join("; ")
      else
        row[field].to_s
      end
    end

    # One normalised row per sheet line. Called by ImportParsing's parsers.
    # Returns nil for a wholly blank line so trailing sheet padding is ignored
    # rather than reported as thirty nameless budgets.
    def normalize_row(raw)
      @header_for ||= resolve_headers(raw.keys)
      return nil if raw.values.all?(&:blank?)

      raw_amount = cell(raw, :amount)
      amount = parse_amount(raw_amount)
      {
        area: text(raw, :area).strip.presence,
        # Lenient like the amount column's own blank case, not blocking like
        # its unreadable one: a mistyped Area Budget cell is caught by
        # #area_total_conflicts as soon as a later row for the same area
        # reads differently, so nothing is lost by treating it as unstated
        # here rather than failing the whole sheet over one cell.
        area_budget: AmountParser.parse(cell(raw, :area_budget)),
        name: text(raw, :name).strip,
        nominal_code: cell(raw, :nominal_code).to_s.strip,
        budget_type: normalize_type(cell(raw, :budget_type)),
        amount: amount,
        # Only kept when it couldn't be read, so the error can quote what was
        # actually typed. Keeping it always would make a row that survived a
        # TSV round-trip ("£1,200" -> "1200.0") differ from the row it came
        # from, for no gain.
        raw_amount: (raw_amount.to_s.strip if amount == :unreadable),
        owner_emails: split_emails(cell(raw, :owner_emails)),
        notes: text(raw, :notes)
      }
    end

    def cell(raw, field)
      raw[header_for[field]]
    end

    # Escape sequences are undone only for text that came back from #to_tsv —
    # never for the operator's own paste, where a backslash is a backslash.
    def text(raw, field)
      value = cell(raw, field)
      @escaped && TEXT_FIELDS.include?(field) ? unescape_cell(value) : value.to_s
    end

    # --- Which column is which -----------------------------------------------

    def resolve_headers(headers)
      FIELDS.transform_values { |spec| match_header(headers, spec) }
    end

    # Two fields reading the same column is refused rather than resolved: which
    # of them the operator meant is exactly what cannot be guessed, and picking
    # one writes the wrong value into a name or a figure with nothing on screen
    # to say so.
    def ambiguous_columns
      header_for.compact.group_by { |_field, header| header }
                .select { |_header, pairs| pairs.size > 1 }
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

      # A problem with the SHEET is one problem, not thirty broken lines.
      report_ambiguous_columns
      report_missing_columns
      return [] if @errors.any?

      duplicated = duplicated_names
      @rows.map { |row| entry_for(row, duplicated) }
    end

    def report_ambiguous_columns
      ambiguous_columns.each do |header, pairs|
        labels = pairs.map { |field, _| FIELDS.fetch(field)[:label] }
        @errors << "The column #{header.inspect} would be read as both " \
                   "#{labels.to_sentence(last_word_connector: ' and ')}. Rename one of them, " \
                   "or start from the template."
      end
    end

    # Judged on the HEADERS, not the values: a sheet that does have a Budget
    # column but left one cell empty gets that row flagged by itself, not the
    # whole sheet rejected.
    def report_missing_columns
      missing = REQUIRED_FIELDS.reject { |field| header_for[field] }
                               .map { |field| FIELDS.fetch(field)[:label] }
      return if missing.empty?

      @errors << "Couldn't find a budget name column. Name one of the columns " \
                 "#{FIELDS.fetch(:name)[:exact].map(&:inspect).to_sentence(last_word_connector: ' or ')}, " \
                 "or start from the template."
    end

    def entry_for(row, duplicated)
      owners, unknown = resolve_owners(row)
      base = { row: row, owner_ids: owners, unknown_owner_emails: unknown, area_name: row[:area] }
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

    # Area names as the sheet actually typed them, keyed by #match_key and kept
    # in the order they first appear — so a re-typed "cogito " on a later line
    # doesn't shadow the casing #area_creates should hand the store. Excludes
    # :invalid entries (a typo there must not mint an area for a row that will
    # never be written).
    def first_seen_names
      (@entries - entries_in(:invalid)).each_with_object({}) do |entry, names|
        next if entry.area_name.blank?

        names[self.class.match_key(entry.area_name)] ||= entry.area_name
      end
    end

    # #match_key(area name) => the DISTINCT, non-blank Area Budget amounts the
    # sheet gives that area — in the order they're first seen, so #area_creates
    # can take the single one it expects and #area_total_conflicts can name
    # every one of a genuine disagreement. Same :invalid exclusion as
    # #first_seen_names, for the same reason.
    def area_budget_totals
      (@entries - entries_in(:invalid)).each_with_object(Hash.new { |h, k| h[k] = [] }) do |entry, totals|
        next if entry.area_name.blank?

        value = entry.row[:area_budget]
        next if value.nil?

        key = self.class.match_key(entry.area_name)
        totals[key] << value unless totals[key].include?(value)
      end
    end

    def report_area_total_conflicts
      area_total_conflicts.each do |conflict|
        amounts = conflict[:values].map { |value| value.to_s("F") }
                                   .to_sentence(last_word_connector: " and ")
        @errors << "#{conflict[:area_name].inspect} has more than one Area Budget figure in " \
                   "this sheet (#{amounts}). Make every line for the area agree, or leave the " \
                   "column blank."
      end
    end

    # +area_id:+ for a line naming an area already here, +area_name:+ for one
    # this import is about to create, or neither for an area-less line.
    def area_attrs_for(entry)
      return {} if entry.area_name.blank?

      existing = @existing_areas_by_name[self.class.match_key(entry.area_name)]
      existing ? { area_id: existing.record_id } : { area_name: entry.area_name }
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
