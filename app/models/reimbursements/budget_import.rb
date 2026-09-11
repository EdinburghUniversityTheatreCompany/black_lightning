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
      # By id as well as by name: #re_homes compares the budget's CURRENT area
      # to the sheet's target by record identity, and separately has to know
      # whether that current area is inside this import's (year, cost centre)
      # at all — two different questions that a name lookup can't tell apart.
      @existing_areas_by_id = existing_areas.index_by(&:record_id)
      @people_by_email = people.index_by { |person| person.email.to_s.strip.downcase }
      # By record id too: #area_owner_sets names the people an area is about to
      # gain, and resolve_owners has already reduced them to ids by then. The
      # preview must never reach for a record of its own.
      @people_by_record_id = people.index_by(&:record_id)
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

    # #area_creates narrowed to the areas something will ACTUALLY land in: an
    # area named on a :create line, or one named by a re-home the operator left
    # TICKED. Apply passes this rather than #area_creates itself.
    #
    # Without it, unticking every re-home on a pure re-import still minted the
    # area — the exact orphan this bucket exists to prevent, arrived at by
    # taking the cautious option the bucket offers. Silently creating an empty
    # container is the same failure as silently moving a line.
    #
    # At PREVIEW time every re-home is ticked, so this and #area_creates agree
    # — which is why the preview's "(new)" markers and its button count can
    # keep reading the unnarrowed list.
    def area_creates_for(re_homes)
      wanted = (entries_in(:create).map(&:area_name) + re_homes.map { |re_home| re_home[:area_name] })
               .compact_blank.map { |name| self.class.match_key(name) }.to_set
      area_creates.select { |attrs| wanted.include?(self.class.match_key(attrs[:name])) }
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

    # Matched lines the sheet puts in a DIFFERENT area than they are in now —
    # reported for the operator to confirm, never applied on sight. Somebody
    # moved that budget on purpose, through the area form or the budget form's
    # picker, so this is the same temperament #absent_budgets already has: the
    # sheet is the committee's record, but a hand-made grouping is somebody's
    # decision, and the sheet is not allowed to overrule it silently.
    #
    # [{ budget_id:, budget_name:, from_area_name:, from_area_scope:,
    #    to_area_name:, to_area_is_new:, to_area_has_owners:, key: }], plus the
    # +area_id:+ / +area_name:+ pair #creates carries — the target is an id
    # when the area is already here and a NAME when this same import is about
    # to create it, and import_budgets! resolves the name inside its
    # transaction exactly as it does for a create. Everything the preview's
    # label needs is on the hash for the same reason +budget_name+ is: the
    # view must never reach for a record.
    #
    # +key+ is the checkbox value, and it is the BUDGET ID rather than a row
    # position: a re-import with the rows reordered must not land a tick on a
    # different line. (Reconcile keys its offsetting pairs by row content plus
    # an occurrence index only because its rows have no id of their own.)
    #
    # Same buckets as #adoptions and #owner_syncs — a matched line is matched
    # whether or not its figure moved.
    #
    # A re-home FROM NIL is the case that stops #area_creates minting orphans:
    # on a re-import every line already exists, and only a :create line carries
    # an area_id, so an area named on a sheet whose lines all match would
    # otherwise be created with no budget in it. That is the common shape —
    # a committee adding an Area column to a sheet they have imported before.
    #
    # A budget that HAS an area whose sheet leaves the cell BLANK is not a
    # re-home to nowhere: a blank cell means "the sheet says nothing", the same
    # reading bucket_for gives a blank Amount.
    #
    # THE COMPARISON IS BY RECORD, NOT BY NAME. Areas are named per show and
    # shows recur, so "Cogito" exists once per Fringe — and a budget in THIS
    # year may legitimately hold LAST year's area (inherit_area_scoping fills
    # blanks only and never checks the year, and BudgetsController appends the
    # budget's own area to the scoped select precisely so such a row survives a
    # save). Matching on the name read that as "already there" and reported
    # nothing, while the line's spend kept rolling up into the other year's
    # area total (Area#committed_amount sums its budgets with no year filter)
    # and that year's owners kept gating the claim.
    def re_homes
      @re_homes ||= (entries_in(:revise) + entries_in(:unchanged)).filter_map do |entry|
        next if entry.area_name.blank?

        key = self.class.match_key(entry.area_name)
        current = entry.budget.area
        existing = @existing_areas_by_name[key]
        next if current && existing && current.record_id == existing.record_id

        re_home_for(entry, key, current, existing)
      end
    end

    # Owner lists for budgets that already exist and are in NO area. The sheet
    # is the committee's own record of who runs what, so a re-import keeps it
    # current — but only where the sheet actually named someone, since an empty
    # owner column means "not stated", not "nobody".
    #
    # A line that HAS an area is #area_owner_syncs' business instead: Budget#owners
    # reads through the area, so the sheet's owner written to the line's own rows
    # is an owner nobody reads and no claim's sign-off gate ever consults.
    #
    # Still compared against the budget's OWN owner rows, because that is what
    # DatabaseStore#sync_budget_owners! writes. With the narrowing above the two
    # reads happen to agree (Budget#owners IS own_owners with no area), so this
    # states which of them the comparison depends on rather than relying on that
    # coincidence — reading the area-resolved Budget#owner_ids is what could
    # never converge, and re-reported the identical sync for ever.
    #
    # A matched AREA-LESS line whose sheet names an area is reported here AND in
    # #area_owner_syncs, deliberately: the sheet's area only takes effect if the
    # operator leaves that re-home ticked, and this model cannot know. Written
    # both places, the owner gates the claim either way.
    def owner_syncs
      (entries_in(:revise) + entries_in(:unchanged)).filter_map do |entry|
        next if entry.owner_ids.empty?
        next if entry.budget.area
        next if entry.budget.own_owners.map(&:record_id).sort == entry.owner_ids.map(&:to_s).sort

        { budget_id: entry.budget.record_id, owner_ids: entry.owner_ids }
      end
    end

    # Owner lists for the AREAS the sheet's lines resolve to — [{ owner_ids: }]
    # plus the same +area_id:+ / +area_name:+ pair #creates and #re_homes carry,
    # so an area this very import is about to create is resolved inside
    # import_budgets!' transaction exactly as a budget's area is.
    #
    # THE AREA'S OWNERS ARE THE UNION of what its lines name, and a sync NEVER
    # REMOVES one — +owner_ids+ is the area's current owners plus the sheet's,
    # and DatabaseStore#add_area_owners! unions again at write time. The sheet
    # has one owner column per LINE, so three lines under one area can name
    # three people and all three are meant; and it has no way at all to say
    # "remove this owner", a blank cell being the same "the sheet says nothing"
    # a blank Amount is. Union is also the forgiving direction — any one owner
    # satisfies the gate, so an extra owner can endorse while a missing one
    # strands the claim — and it is what AreaBackfill#seed_owners! already did.
    # Removal stays hand-work on the area form.
    #
    # Nothing is reported when the sheet names only people the area already has:
    # the union is then unchanged.
    def area_owner_syncs
      owner_targets.each_value.filter_map do |target|
        current = target[:area]&.owner_ids || []
        next if (target[:owner_ids] - current).empty?

        area_attrs_for_target(target).merge(owner_ids: current | target[:owner_ids])
      end
    end

    # What each of those areas will END UP naming, for the preview:
    # [{ area_name:, area_is_new:, owners: [{ name:, added: }] }].
    #
    # A NAMED LIST rather than a count, because the union is forgiving in both
    # directions: a stale address on one line otherwise gains sign-off authority
    # over a whole show with nothing on screen to say so. It shows the area's
    # existing owners alongside the ones these lines add — since a sync never
    # subtracts, that IS what the area will hold afterwards.
    def area_owner_sets
      owner_targets.each_value.map do |target|
        current = target[:area]&.owners || []
        added = target[:owner_ids] - current.map(&:record_id)
        { area_name: target[:area_name], area_is_new: target[:area].nil?,
          owners: current.map { |person| { name: person.name, added: false } } +
                  added.map { |id| { name: @people_by_record_id[id]&.name, added: true } } }
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
        case row[:area_budget]
        when nil then ""
        when :unreadable then row[:raw_area_budget].to_s
        else row[:area_budget].to_s("F")
        end
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
      raw_area_budget = cell(raw, :area_budget)
      area_budget = parse_amount(raw_area_budget)
      {
        area: text(raw, :area).strip.presence,
        # Same blank/unreadable split as :amount, via the same #parse_amount —
        # blank (nothing typed) stays nil, the normal state for an area with no
        # agreed total yet; unreadable ("£1,2OO") is a BLOCKING row error, not
        # silently read as unstated, because that would be an area created
        # with no agreed total and nobody told. #row_error below reports it.
        area_budget: area_budget,
        name: text(raw, :name).strip,
        nominal_code: cell(raw, :nominal_code).to_s.strip,
        budget_type: normalize_type(cell(raw, :budget_type)),
        amount: amount,
        # Only kept when it couldn't be read, so the error can quote what was
        # actually typed. Keeping it always would make a row that survived a
        # TSV round-trip ("£1,200" -> "1200.0") differ from the row it came
        # from, for no gain.
        raw_amount: (raw_amount.to_s.strip if amount == :unreadable),
        raw_area_budget: (raw_area_budget.to_s.strip if area_budget == :unreadable),
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
      elsif row[:area_budget] == :unreadable
        "#{row[:raw_area_budget].inspect} isn't an amount for #{area_label(row)}'s Area Budget. " \
          "Leave it blank if the total isn't agreed yet."
      elsif Budget::TYPES.exclude?(row[:budget_type])
        "#{row[:budget_type].inspect} isn't a budget type. Use #{Budget::TYPES.to_sentence(last_word_connector: ' or ')}."
      end
    end

    # For the unreadable-Area-Budget row error: names the area when the row
    # gives one, so the operator knows which show's total is wrong even
    # though the bad row is (necessarily) reported by itself rather than
    # grouped with the area's other rows the way #area_total_conflicts does.
    def area_label(row)
      row[:area].presence&.inspect || "this line"
    end

    # Area names as the sheet actually typed them, keyed by #match_key and kept
    # in the order they first appear — so a re-typed "cogito " on a later line
    # doesn't shadow the casing #area_creates should hand the store. Excludes
    # :invalid entries (a typo there must not mint an area for a row that will
    # never be written).
    def first_seen_names
      @first_seen_names ||= (@entries - entries_in(:invalid)).each_with_object({}) do |entry, names|
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

    # grouping key => { area:, area_name:, owner_ids: } for every area the
    # sheet's owner column feeds. One pass, because the three readers above
    # each need the area record, the name to show and the union.
    #
    # Keyed by RECORD ID where the area exists, so two lines reaching the same
    # area merge however they got there — the sheet naming it, and a blank Area
    # cell over a line already sitting in it, are the same area — and by name
    # where this import is about to create it. Excludes :invalid entries for
    # the same reason #first_seen_names does: a typo on a blocked row must not
    # hand a show an owner.
    def owner_targets
      @owner_targets ||= (@entries - entries_in(:invalid)).each_with_object({}) do |entry, targets|
        next if entry.owner_ids.empty?

        area, key, name = resolve_owner_target(entry)
        next if key.nil?

        target = (targets[key] ||= { area: area, area_name: name, owner_ids: [] })
        target[:owner_ids] |= entry.owner_ids
      end
    end

    # [area record or nil, grouping key, area name] for the area a line's named
    # owners belong to — the area the line RESOLVES to, which is the one the
    # sheet names, or the one the budget is already in when the cell is blank.
    # An empty triple for a line that reaches no area at all: its owners stay on
    # the budget's own rows, which for an area-less line is the live read.
    def resolve_owner_target(entry)
      if entry.area_name.present?
        key = self.class.match_key(entry.area_name)
        existing = @existing_areas_by_name[key]
        [ existing, target_key(existing, key), first_seen_names[key] ]
      elsif entry.budget&.area
        area = entry.budget.area
        [ area, target_key(area, nil), area.name ]
      else
        []
      end
    end

    def target_key(area, name_key) = area ? "id:#{area.record_id}" : "name:#{name_key}"

    # The +area_id:+ / +area_name:+ pair for a grouped target, the same shape
    # #area_attrs_for hands #creates.
    def area_attrs_for_target(target)
      target[:area] ? { area_id: target[:area].record_id } : { area_name: target[:area_name] }
    end

    # Whether the area a re-home moves a line into will name SOMEBODY once this
    # import has run: its current owners, plus the ones this sheet's owner
    # column is about to add to it. An address that matched nobody doesn't
    # count — resolve_owners drops it, so the area would still name nobody.
    def area_will_have_owners?(area, name_key)
      return true if area&.owners&.any?

      owner_targets[target_key(area, name_key)].present?
    end

    # +area_id:+ for a line naming an area already here, +area_name:+ for one
    # this import is about to create, or neither for an area-less line.
    def area_attrs_for(entry)
      return {} if entry.area_name.blank?

      existing = @existing_areas_by_name[self.class.match_key(entry.area_name)]
      existing ? { area_id: existing.record_id } : { area_name: entry.area_name }
    end

    # One re-home's hash. Split out of #re_homes so the label's two
    # qualifications sit next to what decides them.
    def re_home_for(entry, key, current, existing)
      { budget_id: entry.budget.record_id, budget_name: entry.budget.name,
        from_area_name: current&.name, from_area_scope: out_of_scope_label(current),
        to_area_name: first_seen_names[key], to_area_is_new: existing.nil?,
        # An area with no owners at all switches its lines' sign-off gate OFF,
        # because Budget#owners resolves THROUGH the area. Read AFTER this
        # import's own owner column: a sheet that names somebody for the area
        # it is moving the line into leaves the gate standing, so warning there
        # would be false. A sheet naming nobody (or only addresses that matched
        # nobody) still lands here — which is why the warning stays.
        to_area_has_owners: area_will_have_owners?(existing, key),
        key: entry.budget.record_id }.merge(area_attrs_for(entry))
    end

    # Why +area+ is outside this import's (financial year, cost centre) — for
    # the preview's label, which would otherwise read "Cogito -> Cogito" for
    # the one case where the names genuinely agree and the records don't. nil
    # for an area inside the scope, which is every ordinary re-home.
    def out_of_scope_label(area)
      return if area.nil? || @existing_areas_by_id.key?(area.record_id)

      parts = []
      parts << area.financial_year.label if area.financial_year && area.financial_year_id != financial_year&.id
      parts << area.cost_centre.name if area.cost_centre && area.cost_centre_id != cost_centre&.id
      parts.join(", ").presence
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
