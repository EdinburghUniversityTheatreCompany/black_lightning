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
  # THE BUCKETS. A line is matched within one (financial year, cost centre) by
  # its AREA plus its bare name where the sheet names an area, and by its whole
  # name otherwise — .bare_name and #resolve_budget read both spellings of a
  # name the area prefix was stripped from.
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
    # A heading not listed here is simply not found — "the sheet has no X
    # column" for a required field, a blank for an optional one. The safe
    # direction: a column read as the WRONG field is silent, one not read at
    # all is stated.
    #
    # **Columns are matched here, NOT through ImportParsing#find_column**,
    # whose "any header containing the keyword" fallback is the class of bug
    # ExpenseImport was fixed for (see its note): "budget" is a bare keyword
    # for +name+, so the "Area Budget" column below would read as the line's
    # own name. EXACT names first, then MULTI-WORD phrases only — a bare word
    # is never a substring hint — and two fields resolving to one column is a
    # blocking error naming both, never a silent pick.
    FIELDS = {
      area: {
        label: "Area",
        exact: [ "area" ],
        # NOT "area", per the class note: the "Area Budget" header contains
        # it, and would then read as the area name too.
        contains: [ "area name" ]
      },
      area_budget: {
        label: "Area Budget",
        # Both multi-word, so neither collides with the bare "area" above or
        # "budget" below.
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

    # The only column a sheet must carry: everything else can be blank or
    # defaulted, but a line with no name has nothing to match against.
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
      @existing_budgets = existing_budgets
      # Grouped, never index_by: a key several stored lines answer to is an
      # ambiguity to report, and index_by keeps the last one silently.
      @existing_by_name = group_by_keys(existing_budgets) do |budget|
        self.class.name_spellings(budget.name, budget.area&.name).map { |spelling| self.class.match_key(spelling) }
      end
      @existing_by_area_and_name = group_by_keys(existing_budgets) do |budget|
        [ self.class.area_scoped_key(budget.name, budget.area&.name) ]
      end
      # Grouped for the same reason: two areas under one name would be a
      # last-wins pick in #re_homes, which moves a line's spend and its gate.
      @existing_areas_by_name = group_by_keys(existing_areas) do |area|
        [ self.class.match_key(area.name) ]
      end
      # By id as well as by name: #re_homes asks both whether two areas are
      # the same record and whether one is in scope at all, and a name lookup
      # cannot tell those apart.
      @existing_areas_by_id = existing_areas.index_by(&:record_id)
      @people_by_email = people.index_by { |person| person.email.to_s.strip.downcase }
      # #area_owner_sets names the people an area is about to gain, and
      # resolve_owners has reduced them to ids by then; the preview must never
      # reach for a record of its own.
      @people_by_record_id = people.index_by(&:record_id)
      @rows = parse_data(data, @escaped ? :paste : input_type)
      @entries = categorize
      report_area_total_conflicts
      report_area_collation_clashes
    end

    # Names are matched case- and space-insensitively: a committee retypes
    # "Props" as "props " every other year.
    def self.match_key(name)
      name.to_s.strip.downcase.squeeze(" ")
    end

    # +name+ with its "Area: " prefix removed — the naming convention areas
    # replaced — but ONLY when that prefix is this line's own area's name.
    # "Rehearsal room hire" under Cogito is somebody's own wording, and
    # "Improverts: Retreat" filed under Cogito names another show; neither is
    # this rule's to rewrite.
    #
    # AreaRename rewrites the stored rows by this exact call, which is why the
    # rule is stated once, here. The committee's spreadsheet keeps saying
    # "Cogito: Marketing" long after the stored line became "Marketing", so a
    # matcher reading one spelling buckets the whole show as new lines — 17 of
    # the 31 live Fringe budgets duplicated in one apply, each with a fresh
    # initial_budget and the original reported absent.
    def self.bare_name(name, area_name)
      return name.to_s if area_name.blank?

      prefix, colon, rest = name.to_s.partition(":")
      return name.to_s if colon.empty? || rest.strip.empty?
      return name.to_s unless match_key(prefix) == match_key(area_name)

      rest.strip
    end

    # Qualified by the area, so two shows that each run a "Marketing" line are
    # two keys rather than one collision — the state stripping the prefixes
    # leaves behind. nil for a line naming no area; those fall to the name
    # lookup.
    def self.area_scoped_key(name, area_name)
      return nil if area_name.blank?

      [ match_key(area_name), match_key(bare_name(name, area_name)) ]
    end

    # A collision is usually two identical names, so the AREA tells them
    # apart — and where two areas share a name (lenient year scoping puts an
    # unstamped Cogito beside a real one), the year and centre do. Qualified
    # only where needed, so the ordinary message stays short.
    def self.budget_labels(budgets)
      labels = budgets.map { |budget| budget_label(budget) }
      return labels if labels.uniq.size == labels.size

      budgets.map { |budget| budget_label(budget, qualified: true) }
    end

    # NOT the display name a screen shows (Budget#display_name): this is the
    # importer's ambiguity wording, which has to name the area SEPARATELY so
    # "in no area" reads as a sentence and a colliding area can be qualified
    # by its year and centre.
    def self.budget_label(budget, qualified: false)
      return "#{budget.name.inspect} in no area" if budget.area.nil?

      "#{budget.name.inspect} in #{qualified ? area_label(budget.area) : budget.area.name}"
    end

    # A blank year/centre pair is what makes the lenient scoping put a legacy
    # area in every year's list to begin with.
    def self.area_label(area)
      parts = [ area.financial_year&.label, area.cost_centre&.name ].compact_blank
      parts.any? ? "#{area.name} (#{parts.join(', ')})" : "#{area.name} (no financial year or cost centre)"
    end

    # As stored, and with its area's prefix put on or taken off. The STORED
    # row knows its own area whether or not the sheet names one, so the
    # committee's untouched old file (prefixed names, no Area column) still
    # finds "Marketing" in Cogito. Both importers key on this.
    def self.name_spellings(name, area_name)
      return [ name.to_s ] if area_name.blank?

      bare = bare_name(name, area_name)
      bare == name.to_s ? [ name.to_s, "#{area_name}: #{name}" ] : [ name.to_s, bare ]
    end

    # Nothing is written unless every row is readable — a partial import leaves
    # the operator reconciling a half-built year against the spreadsheet by eye.
    def valid?
      @errors.empty? && @entries.any? && @entries.none? { |entry| entry.bucket == :invalid }
    end

    def entries_in(bucket) = @entries.select { |entry| entry.bucket == bucket }

    # Attributes for each new budget, ready for the store. A line naming an
    # AREA carries +area_id:+ (an area already here) or +area_name:+ (one the
    # sheet is about to create), never both; import_budgets! resolves the name
    # inside its transaction, once #area_creates has run.
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
    # the sheet names that isn't already here — matched by name within one
    # (financial year, cost centre), as a budget line is, and never deleted for
    # #absent_budgets' reason.
    #
    # Reads every entry the sheet KEPT (create/revise/unchanged), not only
    # #creates: an area can be named on a line that matches an existing budget.
    # :invalid rows are excluded, so a typo can't mint an area for a row that
    # will never be written.
    #
    # +initial_budget+ is written ONLY on create, the write-once rule
    # Budget#initial_budget follows.
    def area_creates
      totals = area_budget_totals
      first_seen_names.except(*@existing_areas_by_name.keys).map do |key, name|
        { name: name, cost_centre: cost_centre, financial_year: financial_year,
          initial_budget: totals[key]&.first }
      end
    end

    # #area_creates narrowed to the areas something will ACTUALLY land in — a
    # :create line's, or a re-home the operator left TICKED. Apply passes this
    # rather than #area_creates: without it, unticking every re-home on a pure
    # re-import still minted the area, so taking the cautious option the bucket
    # offers produced the orphan it exists to prevent.
    #
    # At PREVIEW time every re-home is ticked, so this and #area_creates agree,
    # and the preview's "(new)" markers can read the unnarrowed list.
    def area_creates_for(re_homes)
      wanted = (entries_in(:create).map(&:area_name) + re_homes.map { |re_home| re_home[:area_name] })
               .compact_blank.map { |name| self.class.match_key(name) }.to_set
      area_creates.select { |attrs| wanted.include?(self.class.match_key(attrs[:name])) }
    end

    # {area_id:, area_name:, from:, amount:} per area the sheet gives a
    # DIFFERENT agreed total than the one stored — the area-level twin of
    # #revisions, logged as a forecast under the same BudgetUpdate.
    #
    # +initial_budget+ on an area stays write-once, exactly as a budget's is
    # (#area_creates is the only thing that writes it), so Area#variance keeps
    # meaning "drift from the figure the committee agreed". Before this a
    # revised Area Budget on a re-import was not applied, not logged and not
    # reported — and the spreadsheet IS the committee's route for revising a
    # show's agreed total, so the revision silently did nothing.
    #
    # Compared against #projected_amount, which is what a budget revision is
    # compared against: the latest forecast, falling back to the agreed figure.
    def area_revisions
      totals = area_budget_totals
      first_seen_names.filter_map do |key, name|
        amount = totals[key]&.first
        area = existing_area_for(key)
        next if amount.nil? || area.nil? || amount == area.projected_amount

        { area_id: area.record_id, area_name: name, from: area.projected_amount, amount: amount }
      end
    end

    # Every area the sheet gives more than one distinct Area Budget figure.
    # The column repeats down the area's rows, so two values can't both be what
    # the committee agreed: #valid? refuses the whole import rather than
    # picking one, as it does for an unreadable Amount.
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
    # moved that budget by hand, and the sheet doesn't get to overrule that
    # silently, the temperament #absent_budgets already has.
    #
    # Carries #creates' +area_id:+ / +area_name:+ pair — a name when this same
    # import is about to create the target, resolved inside import_budgets!'
    # transaction as a create's is.
    #
    # +key+ is the checkbox value and it is the BUDGET ID, not a row position:
    # a re-import with the rows reordered must not land a tick on another line.
    #
    # A budget that HAS an area whose sheet leaves the cell BLANK is not a
    # re-home to nowhere: a blank cell says nothing, the reading bucket_for
    # gives a blank Amount.
    #
    # THE COMPARISON IS BY RECORD, NOT BY NAME. "Cogito" exists once per
    # Fringe, and a budget in THIS year may legitimately hold LAST year's area
    # (inherit_area_scoping fills blanks only and never checks the year).
    # Matching on the name read that as "already there" and reported nothing,
    # while the line's spend kept rolling into the other year's area total
    # (Area#committed_amount has no year filter) and that year's owners kept
    # gating the claim.
    def re_homes
      @re_homes ||= (entries_in(:revise) + entries_in(:unchanged)).filter_map do |entry|
        next if entry.area_name.blank?

        key = self.class.match_key(entry.area_name)
        current = entry.budget.area
        existing = existing_area_for(key)
        next if current && existing && current.record_id == existing.record_id

        re_home_for(entry, key, current, existing)
      end
    end

    # Owner lists for budgets that already exist and are in NO area. The sheet
    # is the committee's own record of who runs what, so a re-import keeps it
    # current — but only where the sheet actually named someone, since an empty
    # owner column means "not stated", not "nobody".
    #
    # A line that HAS an area is #area_owner_syncs' business instead:
    # Budget#owners reads through the area, so the sheet's owner written to such
    # a line's own rows is one no sign-off gate ever consults.
    #
    # Compared against the budget's OWN owner rows, because that is what
    # DatabaseStore#sync_budget_owners! writes — comparing the area-resolved
    # Budget#owner_ids could never converge, and re-reported the identical sync
    # for ever.
    #
    # A matched AREA-LESS line whose sheet names an area is reported here AND in
    # #area_owner_syncs, deliberately: the sheet's area takes effect only if the
    # operator leaves that re-home ticked, which this model cannot know.
    def owner_syncs
      (entries_in(:revise) + entries_in(:unchanged)).filter_map do |entry|
        next if entry.owner_ids.empty?
        next if entry.budget.area
        next if entry.budget.own_owners.map(&:record_id).sort == entry.owner_ids.map(&:to_s).sort

        { budget_id: entry.budget.record_id, owner_ids: entry.owner_ids }
      end
    end

    # Owner lists for the AREAS the sheet's lines resolve to — [{ owner_ids: }]
    # plus the +area_id:+ / +area_name:+ pair #creates and #re_homes carry.
    #
    # THE AREA'S OWNERS ARE THE UNION of what its lines name, and a sync NEVER
    # REMOVES one (DatabaseStore#add_area_owners! unions again at write time,
    # and states why). Union is the forgiving direction: any one owner satisfies
    # the gate, so an extra can endorse while a missing one strands the claim.
    # It is what AreaBackfill#seed_owners! already did.
    def area_owner_syncs
      owner_targets.each_value.filter_map do |target|
        current = target[:area]&.owner_ids || []
        next if (target[:owner_ids] - current).empty?

        area_attrs_for_target(target).merge(owner_ids: current | target[:owner_ids])
      end
    end

    # What each of those areas will END UP naming, for the preview.
    #
    # A NAMED LIST rather than a count: the union is forgiving in both
    # directions, so a stale address on one line would otherwise gain sign-off
    # authority over a whole show with nothing on screen to say so. Existing
    # owners are shown beside the ones these lines add, which since a sync never
    # subtracts IS what the area ends up holding.
    #
    # +area_scope+ is the re-home label's qualification, and it is what makes
    # the blank-Area-cell reading safe: a blank cell targets the area the budget
    # is already IN, which may be another year's (see #re_homes), and that line
    # reports no re-home — so two different "Cogito"s would otherwise render as
    # two identical lines.
    def area_owner_sets
      owner_targets.each_value.map do |target|
        current = target[:area]&.owners || []
        added = target[:owner_ids] - current.map(&:record_id)
        { area_name: target[:area_name], area_is_new: target[:area].nil?,
          area_scope: out_of_scope_label(target[:area]),
          owners: current.map { |person| { name: person.name, added: false } } +
                  added.map { |id| { name: @people_by_record_id[id]&.name, added: true } } }
      end
    end

    # Lines already in this year that the sheet doesn't mention.
    def absent_budgets
      named = @entries.filter_map { |entry| entry.budget&.record_id }.to_set
      @existing_budgets.reject { |budget| named.include?(budget.record_id) }
    end

    # What an apply will DO, keyed by the DatabaseStore#import_budgets! argument
    # that does it, each value a [label, count] pair for the preview's submit
    # button.
    #
    # Keyed that way so the two cannot drift: budget_import_test asserts this
    # covers every argument import_budgets! takes apart from the two that carry
    # no work. Before that, the button counted areas, creates, revisions and
    # re-homes only — so an owner-only sheet (an area that already exists, a
    # line already in it, the same figure, and an Owner emails column naming
    # somebody) rendered the owner panel naming the new owner directly above a
    # DISABLED button reading "Nothing to import". That is a control failure,
    # not cosmetics: the owner never lands, the area still names nobody,
    # OwnerReview.gate_applies? stays false, and every claim on that show skips
    # budget-owner sign-off.
    #
    # +re_homes+ is the TICKED list, so the label and the areas counted for it
    # say what apply will write; at preview time every box is ticked.
    def apply_work(re_homes: self.re_homes)
      { area_creates: [ "new area", area_creates_for(re_homes).size ],
        creates: [ "new budget", entries_in(:create).size ],
        revisions: [ "changed figure", revisions.size ],
        area_revisions: [ "revised area total", area_revisions.size ],
        re_homes: [ "moved line", re_homes.size ],
        adoptions: [ "adopted line", adoptions.size ],
        owner_syncs: [ "owner update", owner_syncs.size ],
        area_owner_syncs: [ "area owner update", area_owner_syncs.size ] }
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
    # can only ever be nearly right, so stating what was read beats tuning it.
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
        # Same blank/unreadable split as :amount. Blank is the normal state
        # for an area with no agreed total yet; unreadable ("£1,2OO") is a
        # BLOCKING row error (#row_error), because reading it as unstated
        # creates the area with no agreed total and tells nobody.
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

    # Refused rather than resolved: which field the operator meant is exactly
    # what cannot be guessed, and picking one writes the wrong value into a name
    # or a figure with nothing on screen to say so.
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

      duplicates = duplicate_rows
      flag_shared_budgets(@rows.each_index.map { |index| entry_for(index, duplicates) })
    end

    # Two rows that resolved to ONE stored line. #duplicated_names compares what
    # the sheet TYPED, so two spellings get past it — "Marketing" and
    # "Cogito: Marketing" with no Area column are two keys and one line, and
    # applying both writes two forecasts to it.
    def flag_shared_budgets(entries)
      counts = entries.filter_map { |entry| entry.budget&.record_id }.tally
      entries.map do |entry|
        next entry unless entry.budget && counts[entry.budget.record_id] > 1

        Entry.new(**entry.to_h, bucket: :invalid, error: shared_budget_error(entry, entries))
      end
    end

    def shared_budget_error(entry, entries)
      rows = entries.select { |other| other.budget&.record_id == entry.budget.record_id }
                    .map(&:row)
      "#{self.class.budget_label(entry.budget)} is named more than once in this sheet " \
        "(#{rows_phrase(rows)}), in more than one way. Name it once."
    end

    def report_ambiguous_columns
      ambiguous_columns.each do |header, pairs|
        labels = pairs.map { |field, _| FIELDS.fetch(field)[:label] }
        @errors << "The column #{header.inspect} would be read as both " \
                   "#{labels.to_sentence(last_word_connector: ' and ')}. Rename one of them, " \
                   "or start from the template."
      end
    end

    # Judged on the HEADERS, not the values: a sheet with a Budget column and
    # one empty cell gets that row flagged, not the whole sheet rejected.
    def report_missing_columns
      missing = REQUIRED_FIELDS.reject { |field| header_for[field] }
                               .map { |field| FIELDS.fetch(field)[:label] }
      return if missing.empty?

      @errors << "Couldn't find a budget name column. Name one of the columns " \
                 "#{FIELDS.fetch(:name)[:exact].map(&:inspect).to_sentence(last_word_connector: ' or ')}, " \
                 "or start from the template."
    end

    def entry_for(index, duplicates)
      row = @rows[index]
      owners, unknown = resolve_owners(row)
      base = { row: row, owner_ids: owners, unknown_owner_emails: unknown, area_name: row[:area] }
      error = row_error(row, duplicates[index])
      return Entry.new(**base, bucket: :invalid, error: error) if error

      budget, match_error = resolve_budget(row)
      return Entry.new(**base, bucket: :invalid, error: match_error) if match_error

      Entry.new(**base, budget: budget, bucket: bucket_for(row, budget))
    end

    # Which stored line this row is about, as [budget, error].
    #
    # TWO SPELLINGS, so two lookups: a sheet still writing "Cogito: Marketing"
    # and a stored line renamed to "Marketing" are the same line, and so is the
    # reverse (somebody may re-prefix a name by hand long afterwards).
    #
    # THE AREA-QUALIFIED LOOKUP WINS, carrying strictly more than the name: the
    # sheet said which show this line belongs to, and two shows each running a
    # "Marketing" line collide on the bare name and not on that key.
    #
    # Neither lookup may GUESS — several stored lines under the deciding key
    # blocks the import naming them, as two fields on one column do. An
    # arbitrary pick revises one show's figure against another's line.
    def resolve_budget(row)
      qualified = stored_under(@existing_by_area_and_name,
                               self.class.area_scoped_key(row[:name], row[:area]))
      return [ nil, ambiguous_match_error(row, qualified) ] if qualified.size > 1
      return [ qualified.sole, nil ] if qualified.size == 1

      plain = stored_under(@existing_by_name, self.class.match_key(row[:name]))
      return [ nil, ambiguous_match_error(row, plain) ] if plain.size > 1

      [ plain.first, nil ]
    end

    def stored_under(index, key) = key.nil? ? [] : index.fetch(key, [])

    # Only reached for an area #row_error let through, so at most one answers
    # to the key; the refusal lives there, once.
    def existing_area_for(name_key) = @existing_areas_by_name.fetch(name_key, []).first

    def colliding_areas(name_key)
      areas = @existing_areas_by_name.fetch(name_key, [])
      areas if areas.size > 1
    end

    def ambiguous_area_error(row, areas)
      "#{row[:area].inspect} matches more than one area already here " \
        "(#{areas.map { |area| self.class.area_label(area) }.to_sentence(last_word_connector: ' and ')}). " \
        "Rename one of them so it's clear which this line belongs to."
    end

    def ambiguous_match_error(row, budgets)
      "#{row[:name].inspect} matches more than one budget already here " \
        "(#{self.class.budget_labels(budgets).to_sentence(last_word_connector: ' and ')}). " \
        "Rename one of them so it's clear which line this figure is for."
    end

    # The preview's bullet shows the name and nothing else, so the AREA CELL is
    # what tells two rows of one name apart — and where even that is the same,
    # saying how many beats listing one label twice.
    def rows_phrase(rows)
      labels = rows.map { |row| row_label(row) }
      return "#{labels.first}, #{labels.size} times" if labels.uniq.one?

      labels.to_sentence(last_word_connector: " and ")
    end

    def row_label(row)
      row[:area].present? ? "#{row[:name].inspect} (#{row[:area]})" : "#{row[:name].inspect} (no area)"
    end

    def group_by_keys(records)
      records.each_with_object({}) do |record, index|
        yield(record).compact.uniq.each { |key| (index[key] ||= []) << record }
      end
    end

    def bucket_for(row, budget)
      return :create if budget.nil?
      # No figure in the sheet means "leave this line as it is", never zero.
      return :unchanged if row[:amount].nil?

      row[:amount] == budget.projected_amount ? :unchanged : :revise
    end

    def row_error(row, twins)
      if row[:name].blank?
        "This line has no budget name, so there's nothing to create or match it against."
      elsif twins.any?
        duplicate_rows_error(row, twins)
      elsif row[:amount] == :unreadable
        "#{row[:raw_amount].inspect} isn't an amount. Leave it blank to keep the current figure."
      elsif row[:area_budget] == :unreadable
        "#{row[:raw_area_budget].inspect} isn't an amount for #{area_label(row)}'s Area Budget. " \
          "Leave it blank if the total isn't agreed yet."
      elsif row[:area].present? && (areas = colliding_areas(self.class.match_key(row[:area])))
        ambiguous_area_error(row, areas)
      elsif Budget::TYPES.exclude?(row[:budget_type])
        "#{row[:budget_type].inspect} isn't a budget type. Use #{Budget::TYPES.to_sentence(last_word_connector: ' or ')}."
      end
    end

    # Two rows of one name are ONE line here, which is right when the sheet
    # types the same line twice and wrong when a Termtime overhead called
    # "Marketing" sits beside a show's. Telling those apart needs the AREA
    # cell, and only the area-less row can supply one — so "name it once",
    # which would destroy a real line, is said only where every row in the
    # group already names an area (or none of them does).
    def duplicate_rows_error(row, twins)
      group = [ row ] + twins
      instruction =
        if group.any? { |other| other[:area].blank? } && group.any? { |other| other[:area].present? }
          "Give the line with no area its own Area cell, or rename it — two lines are told " \
            "apart by their area, not by the name alone."
        else
          "Name it once — two lines are told apart by their area, not by the name alone."
        end

      "The same budget line is named more than once in this sheet " \
        "(#{rows_phrase(group)}). #{instruction}"
    end

    # For the unreadable-Area-Budget row error, which is necessarily reported
    # per row rather than grouped by area as #area_total_conflicts is — so it
    # has to name the show whose total is wrong.
    def area_label(row)
      row[:area].presence&.inspect || "this line"
    end

    # Area names as the sheet typed them, keyed by #match_key, first spelling
    # wins — so a re-typed "cogito " on a later line doesn't shadow the casing
    # #area_creates hands the store. :invalid entries are excluded.
    def first_seen_names
      @first_seen_names ||= (@entries - entries_in(:invalid)).each_with_object({}) do |entry, names|
        next if entry.area_name.blank?

        names[self.class.match_key(entry.area_name)] ||= entry.area_name
      end
    end

    # #match_key(area name) => the DISTINCT, non-blank Area Budget amounts the
    # sheet gives that area, first-seen order — so #area_creates takes the one
    # it expects and #area_total_conflicts can name every one of a genuine
    # disagreement. Same :invalid exclusion as #first_seen_names.
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

    # Area's uniqueness validation queries under utf8mb4_unicode_ci, which FOLDS
    # ACCENTS, while #match_key folds only case and spacing. So a sheet naming
    # "Cógito" where "Cogito" is already here reaches #area_creates as a new
    # area and Area.create! raises RecordInvalid inside apply's transaction — a
    # 500 that loses the operator's forty-line paste instead of a stated,
    # blocking error. Two NEW areas differing only by an accent collide the same
    # way, so the sheet is checked against itself as well.
    #
    # transliterate is broader than the collation in places, and that is the
    # safe direction here: it can only refuse a name the database would have
    # refused anyway.
    def report_area_collation_clashes
      stored = @existing_areas_by_name.each_value.flat_map { |areas| areas }
                                      .index_by { |area| collation_key(area.name) }
      seen = {}
      area_creates.each do |attrs|
        name = attrs[:name]
        key = collation_key(name)
        clash = stored[key]&.name || seen[key]
        if clash
          @errors << "#{name.inspect} and #{clash.inspect} are the same area name as far as "                      "the database is concerned — it ignores accents. Spell the area one way."
        else
          seen[key] = name
        end
      end
    end

    def collation_key(name) = ActiveSupport::Inflector.transliterate(self.class.match_key(name))

    # grouping key => { area:, area_name:, owner_ids: } for every area the
    # sheet's owner column feeds.
    #
    # Keyed by RECORD ID where the area exists, so two lines reaching one area
    # merge however they got there (the sheet naming it, or a blank Area cell
    # over a line already in it), and by name where this import is about to
    # create it. :invalid entries are excluded: a typo on a blocked row must
    # not hand a show an owner.
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
    # owners belong to — the one the sheet names, or the one the budget is
    # already in when the cell is blank. An empty triple for a line reaching no
    # area: its owners stay on the budget's own rows, the live read there.
    def resolve_owner_target(entry)
      if entry.area_name.present?
        key = self.class.match_key(entry.area_name)
        existing = existing_area_for(key)
        [ existing, target_key(existing, key), first_seen_names[key] ]
      elsif entry.budget&.area
        area = entry.budget.area
        [ area, target_key(area, nil), area.name ]
      else
        []
      end
    end

    def target_key(area, name_key) = area ? "id:#{area.record_id}" : "name:#{name_key}"

    def area_attrs_for_target(target)
      target[:area] ? { area_id: target[:area].record_id } : { area_name: target[:area_name] }
    end

    # Whether the target area will name SOMEBODY once this import has run:
    # current owners plus the ones this sheet adds. An address that matched
    # nobody doesn't count — resolve_owners drops it, so the area names nobody.
    def area_will_have_owners?(area, name_key)
      return true if area&.owners&.any?

      owner_targets[target_key(area, name_key)].present?
    end

    def area_attrs_for(entry)
      return {} if entry.area_name.blank?

      existing = existing_area_for(self.class.match_key(entry.area_name))
      existing ? { area_id: existing.record_id } : { area_name: entry.area_name }
    end

    def re_home_for(entry, key, current, existing)
      { budget_id: entry.budget.record_id, budget_name: entry.budget.name,
        from_area_name: current&.name, from_area_scope: out_of_scope_label(current),
        to_area_name: first_seen_names[key], to_area_is_new: existing.nil?,
        # An ownerless area switches its lines' sign-off gate OFF, because
        # Budget#owners resolves THROUGH the area. Read AFTER this import's own
        # owner column, or a sheet that names somebody for the target area
        # would warn falsely.
        to_area_has_owners: area_will_have_owners?(existing, key),
        key: entry.budget.record_id }.merge(area_attrs_for(entry))
    end

    # Why +area+ is outside this import's (financial year, cost centre) — the
    # preview's label would otherwise read "Cogito -> Cogito" for the one case
    # where the names agree and the records don't. nil for every ordinary
    # re-home.
    def out_of_scope_label(area)
      return if area.nil? || @existing_areas_by_id.key?(area.record_id)

      parts = []
      parts << area.financial_year.label if area.financial_year && area.financial_year_id != financial_year&.id
      parts << area.cost_centre.name if area.cost_centre && area.cost_centre_id != cost_centre&.id
      parts.join(", ").presence
    end

    # A sheet that has stopped typing prefixes writes "Marketing" once per show,
    # and those are different lines — which is what having areas is for. So a
    # row that names an area is identified BY that area, not by its name alone.
    def row_key(index)
      @row_keys ||= {}
      return @row_keys[index] if @row_keys.key?(index)

      row = @rows[index]
      @row_keys[index] =
        if row[:name].blank?
          nil
        else
          self.class.area_scoped_key(row[:name], row[:area]) ||
            [ nil, self.class.match_key(row[:name]) ]
        end
    end

    # What an AREA-LESS row would be called under each area this sheet names.
    # A half-filled Area column is the likeliest transitional sheet there is,
    # and without this it imports as two budgets of one name with the show's
    # spend split between them. Two area-less rows are never made equal to each
    # other: their own names are all they have to go on.
    def alias_row_keys(index)
      @alias_row_keys ||= {}
      @alias_row_keys[index] ||= begin
        row = @rows[index]
        if row[:name].blank? || row[:area].present?
          []
        else
          sheet_area_names.map { |area| self.class.area_scoped_key(row[:name], area) }
        end
      end
    end

    def sheet_area_names
      @sheet_area_names ||= @rows.filter_map { |row| row[:area].presence }
                                 .uniq { |name| self.class.match_key(name) }
    end

    # Row index => the other rows naming the same budget line.
    #
    # Two rows are one line when they share a key that IDENTIFIES at least one
    # of them, so an alias only ever matches a row that really does name that
    # area. Two groupings rather than every pair: rows that CLAIM a key (their
    # own plus aliases) against rows that OWN one (their own alone).
    def duplicate_rows
      claimants = Hash.new { |index, key| index[key] = [] }
      owners = Hash.new { |index, key| index[key] = [] }
      @rows.each_index do |index|
        next if row_key(index).nil?

        owners[row_key(index)] << index
        all_row_keys(index).each { |key| claimants[key] << index }
      end

      @rows.each_index.to_h do |index|
        [ index, twins_of(index, claimants, owners).map { |other| @rows[other] } ]
      end
    end

    def twins_of(index, claimants, owners)
      return [] if row_key(index).nil?

      (claimants[row_key(index)] |
        all_row_keys(index).flat_map { |key| owners[key] }).sort - [ index ]
    end

    def all_row_keys(index) = [ row_key(index) ] + alias_row_keys(index)

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
