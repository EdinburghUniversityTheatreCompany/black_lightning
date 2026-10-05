module Reimbursements
  ##
  # The committee's budget spreadsheet, read into buckets an operator confirms
  # before anything is written. A pure function of its inputs, so preview and
  # apply each build one from the same text, and apply re-validates rather
  # than trusting the preview.
  #
  # Buckets, within one (financial year, cost centre): create, revise (logged
  # as a forecast), unchanged (same figure, or none given) and invalid, which
  # blocks the WHOLE import. A line is matched by area plus bare name where
  # the sheet names an area, by name otherwise (#resolve_budget).
  # #absent_budgets are reported, never deleted: a budget's claims and history
  # hang off it. +initial_budget+ is written only on create, so
  # Budget#variance keeps meaning drift from the figure the committee agreed.
  #
  # Columns are matched strictly (StrictColumnMatching), NOT through
  # ImportParsing#find_column, whose substring fallback reads the old
  # "Area Budget" heading as the line's name. Two fields on one column block.
  class BudgetImport
    include ImportParsing
    include StrictColumnMatching

    # +declined_namesakes+ are the lines #loose_match passed over.
    Entry = Struct.new(:row, :bucket, :budget, :owner_ids, :unknown_owner_emails, :error,
                       :area_name, :declined_namesakes, :matched_area_label, keyword_init: true) do
      def matched_note
        declined = Array(declined_namesakes)
        return if declined.empty?

        others = BudgetImport.budget_labels(declined).to_sentence(last_word_connector: " and ")
        "Matched #{BudgetImport.budget_label(budget)}. #{others} " \
          "#{declined.one? ? 'is' : 'are'} named the same. Give this row an Area cell if you " \
          "meant #{declined.one? ? 'that one' : 'one of those'}."
      end
    end

    # One entry per column, in #to_tsv order: +label+ is the canonical heading,
    # +exact+ matches a whole header, +contains+ a multi-word substring.
    #
    # Every label must be in its own field's +exact+ list: #to_tsv writes the
    # labels and apply re-parses them, so a label that cannot be read back
    # drops its column between the preview and the apply.
    FIELDS = {
      area: {
        label: "Area",
        hint: "The show or committee this line belongs to",
        exact: [ "area" ],
        # NOT "area": the old "Area Budget" heading contains it.
        contains: [ "area name" ]
      },
      # The old headings ("Area Budget", "Budget", "Amount") stay in +exact+ so
      # the committee's existing sheet still imports.
      area_budget: {
        label: "Area total",
        hint: "The show's agreed total, the same on every row of that area",
        exact: [ "area total", "area budget" ],
        contains: [ "area budget", "area total" ]
      },
      name: {
        label: "Budget name",
        hint: "The line's name, such as Marketing",
        exact: [ "budget name", "name", "line", "category", "budget" ],
        contains: [ "budget name" ]
      },
      nominal_code: {
        label: "Nominal code",
        hint: "The line's nominal code",
        exact: [ "nominal code", "nominal", "code" ],
        contains: [ "nominal code" ]
      },
      budget_type: {
        label: "Type",
        hint: "Expense or Income",
        exact: [ "budget type", "type" ],
        contains: [ "budget type" ]
      },
      amount: {
        label: "Budget amount",
        hint: "This line's own figure",
        exact: [ "budget amount", "amount", "initial budget", "forecast", "total" ],
        contains: [ "initial budget" ]
      },
      owner_emails: {
        label: "Owner emails",
        hint: "Who signs off claims",
        exact: [ "owner emails", "owner email", "owners", "owner" ],
        contains: [ "owner emails", "owner email" ]
      },
      notes: {
        label: "Notes",
        hint: "Free text",
        exact: [ "notes", "description", "comment" ],
        contains: []
      }
    }.freeze

    TSV_HEADERS = FIELDS.each_value.map { |spec| spec[:label] }.freeze

    # The template's second row. A sheet still carrying it has that row
    # skipped, or its words would block the import as an unreadable amount.
    TEMPLATE_HINTS = FIELDS.each_value.map { |spec| spec[:hint] }.freeze

    # The only column a sheet must carry: everything else can be blank or
    # defaulted, but a line with no name has nothing to match against.
    REQUIRED_FIELDS = %i[name].freeze

    OWNER_SEPARATOR = /[,;\s]+/

    # Cells that may hold a tab or newline, so are unescaped in #to_tsv output.
    TEXT_FIELDS = %i[name notes area].freeze

    attr_reader :entries, :financial_year, :cost_centre

    # +input_type+ is :paste, :xlsx, or :canonical_tsv (this class's own
    # #to_tsv coming back from the preview). Only :canonical_tsv is unescaped:
    # doing it to the operator's paste rewrote a typed "C:\temp\report.pdf"
    # before matching it against a stored name.
    def initialize(data, input_type:, financial_year:, cost_centre:, existing_budgets: [],
                  existing_areas: [], people: [])
      @errors = []
      @financial_year = financial_year
      @cost_centre = cost_centre
      @escaped = input_type == :canonical_tsv
      @existing_budgets = existing_budgets
      # Grouped, never index_by: a key several stored lines answer to is an
      # ambiguity to report, and index_by keeps the last one silently. Split by
      # whether the spelling names the line's area ("Cogito: Marketing") or not.
      @existing_by_prefixed_name = group_by_keys(existing_budgets) do |budget|
        self.class.spelling_keys(budget, naming_area: true)
      end
      @existing_by_bare_name = group_by_keys(existing_budgets) do |budget|
        self.class.spelling_keys(budget, naming_area: false)
      end
      @existing_by_area_and_name = group_by_keys(existing_budgets) do |budget|
        [ self.class.area_scoped_key(budget.name, budget.area&.name) ]
      end
      # Grouped too: two areas of one name must block, not be a last-wins pick.
      @existing_areas_by_name = group_by_keys(existing_areas) do |area|
        [ self.class.match_key(area.name) ]
      end
      # By id too: #re_homes compares records, which a name lookup cannot.
      @existing_areas_by_id = existing_areas.index_by(&:record_id)
      @people_by_email = people.index_by { |person| person.email.to_s.strip.downcase }
      @people_by_record_id = people.index_by(&:record_id)
      @rows = parse_data(data, @escaped ? :paste : input_type)
                .reject { |row| row[:name] == FIELDS[:name][:hint] }
      @entries = categorize
      report_area_total_conflicts
      report_area_collation_clashes
    end

    def self.match_key(name)
      name.to_s.strip.downcase.squeeze(" ")
    end

    # +name+ without its "Area: " prefix, but only when the prefix is this
    # line's OWN area: "Improverts: Retreat" under Cogito names another show.
    # AreaRename rewrites stored rows by this exact call. The committee's sheet
    # keeps the prefix after the rename, and reading only one spelling
    # duplicated 17 of the 31 live Fringe budgets in one apply.
    def self.bare_name(name, area_name)
      return name.to_s if area_name.blank?

      prefix, colon, rest = name.to_s.partition(":")
      return name.to_s if colon.empty? || rest.strip.empty?
      return name.to_s unless match_key(prefix) == match_key(area_name)

      rest.strip
    end

    # Qualified by the area, so two shows' "Marketing" lines are two keys.
    # nil for a line in no area, which falls to the name lookup.
    def self.area_scoped_key(name, area_name)
      return nil if area_name.blank?

      [ match_key(area_name), match_key(bare_name(name, area_name)) ]
    end

    # Qualified by year and centre only where two labels would read the same.
    def self.budget_labels(budgets)
      labels = budgets.map { |budget| budget_label(budget) }
      return labels if labels.uniq.size == labels.size

      budgets.map { |budget| budget_label(budget, qualified: true) }
    end

    # Not Budget#display_name: the area is named separately, so "in no area"
    # reads as a sentence and a clashing area can be qualified.
    def self.budget_label(budget, qualified: false)
      return "#{budget.name.inspect} in no area" if budget.area.nil?

      "#{budget.name.inspect} in #{qualified ? area_label(budget.area) : budget.area.name}"
    end

    def self.area_label(area)
      parts = [ area.financial_year&.label, area.cost_centre&.name ].compact_blank
      parts.any? ? "#{area.name} (#{parts.join(', ')})" : "#{area.name} (no financial year or cost centre)"
    end

    # As stored, and with its area's prefix put on or taken off. The stored row
    # knows its area, so an old sheet (prefixed names, no Area column) still
    # finds "Marketing" in Cogito. Both importers key on this.
    def self.name_spellings(name, area_name)
      return [ name.to_s ] if area_name.blank?

      bare = bare_name(name, area_name)
      bare == name.to_s ? [ name.to_s, "#{area_name}: #{name}" ] : [ name.to_s, bare ]
    end

    # The keys a stored line answers to, taking the spellings that do (or do
    # not) name its own area. A PARTITION of .name_spellings, pinned by a test:
    # a lost spelling would be silent, and the line simply stop being findable.
    def self.spelling_keys(budget, naming_area:)
      area_name = budget.area&.name
      name_spellings(budget.name, area_name)
        .select { |spelling| (bare_name(spelling, area_name) != spelling) == naming_area }
        .map { |spelling| match_key(spelling) }
    end

    # All or nothing: a half-imported year would have to be reconciled by eye.
    def valid?
      @errors.empty? && @entries.any? && @entries.none? { |entry| entry.bucket == :invalid }
    end

    def entries_in(bucket) = @entries.select { |entry| entry.bucket == bucket }

    # The area a row LANDS in, rendered so the operator can catch a wrong
    # adoption.
    def area_name_for(entry) = create_area_name(entry)

    # Whether that area came off the row's NAME rather than its cell.
    def area_adopted?(entry) = entry.area_name.blank? && area_name_for(entry).present?

    # A line naming an area carries +area_id:+ (one already here) or
    # +area_name:+ (one this import creates, resolved inside import_budgets!).
    def creates
      entries_in(:create).map do |entry|
        area_name = create_area_name(entry)
        { name: self.class.bare_name(entry.row[:name], area_name),
          nominal_code: entry.row[:nominal_code],
          budget_type: entry.row[:budget_type], initial_budget: entry.row[:amount],
          notes: entry.row[:notes], active: true,
          financial_year: financial_year, cost_centre: cost_centre,
          owner_ids: entry.owner_ids }.merge(area_attrs_for_name(area_name))
      end
    end

    # Areas the sheet names that aren't here yet. Read from every kept row, not
    # only creates: a matched line can name a new area too.
    def area_creates
      totals = area_budget_totals
      first_seen_names.except(*@existing_areas_by_name.keys).map do |key, name|
        { name: name, cost_centre: cost_centre, financial_year: financial_year,
          initial_budget: totals[key]&.first }
      end
    end

    # #area_creates narrowed to areas something lands in: a create's, or a
    # ticked re-home's. Unticking every re-home must not mint an orphan area.
    def area_creates_for(re_homes)
      wanted = (entries_in(:create).map { |entry| create_area_name(entry) } +
                re_homes.map { |re_home| re_home[:area_name] })
               .compact_blank.map { |name| self.class.match_key(name) }.to_set
      area_creates.select { |attrs| wanted.include?(self.class.match_key(attrs[:name])) }
    end

    # Areas whose sheet total differs from Area#projected_amount (the latest
    # forecast, else the agreed figure), logged as forecasts: an area's
    # +initial_budget+ is write-once, as a budget's is.
    def area_revisions
      totals = area_budget_totals
      first_seen_names.filter_map do |key, name|
        amount = totals[key]&.first
        area = existing_area_for(key)
        next if amount.nil? || area.nil? || amount == area.projected_amount

        { area_id: area.record_id, area_name: name, from: area.projected_amount, amount: amount }
      end
    end

    # Areas given more than one distinct Area total. Two values can't both be
    # what the committee agreed, so #valid? refuses rather than picking one.
    def area_total_conflicts
      area_budget_totals.filter_map do |key, values|
        next if values.size <= 1

        { area_name: first_seen_names[key], values: values }
      end
    end

    def revisions
      entries_in(:revise).map do |entry|
        { budget_id: entry.budget.record_id, amount: entry.row[:amount] }
      end
    end

    # Matched lines in no cost centre, claimed by the one this import is for.
    # Lenient scoping puts an unplaced line in every centre's list, so without
    # this two committees' sheets would take turns revising one shared row.
    def adoptions
      return [] if cost_centre.nil?

      (entries_in(:revise) + entries_in(:unchanged)).filter_map do |entry|
        next if entry.budget.cost_centre_id

        { budget_id: entry.budget.record_id, cost_centre: cost_centre }
      end
    end

    # Matched lines the sheet puts in a different area than they are in now,
    # reported for the operator to tick and never applied on sight: somebody
    # may have moved the line by hand. Carries #creates' +area_id:+ /
    # +area_name:+. +key+ is the checkbox value and is the BUDGET ID, not a row
    # position, so a reordered re-import cannot land a tick on another line.
    #
    # A blank Area cell says nothing; it is not a re-home to nowhere.
    #
    # THE COMPARISON IS BY RECORD, NOT BY NAME: a budget may hold another
    # year's same-named "Cogito", and a name match would leave its spend and
    # its sign-off in that year's area.
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

    # Owner lists for matched lines in NO area (an area-bound line's are
    # #area_owner_syncs'), only where the sheet named someone: a blank cell is
    # "not stated", not "nobody". Compared against the budget's OWN owner rows,
    # which sync_budget_owners! writes; comparing the area-resolved owner_ids
    # never converged. An area-less line the sheet re-homes is in both lists,
    # since the move depends on the tick.
    def owner_syncs
      (entries_in(:revise) + entries_in(:unchanged)).filter_map do |entry|
        next if entry.owner_ids.empty?
        next if entry.budget.area
        next if entry.budget.own_owners.map(&:record_id).sort == entry.owner_ids.map(&:to_s).sort

        { budget_id: entry.budget.record_id, owner_ids: entry.owner_ids }
      end
    end

    # Owner lists for the areas the sheet's lines resolve to. An area's owners
    # are the UNION of what its lines name and a sync never removes one: any
    # owner satisfies the gate, so an extra can endorse while a missing one
    # strands the claim.
    def area_owner_syncs
      owner_targets.each_value.filter_map do |target|
        current = target[:area]&.owner_ids || []
        next if (target[:owner_ids] - current).empty?

        area_attrs_for_target(target).merge(owner_ids: current | target[:owner_ids])
      end
    end

    # What each of those areas ends up naming: a named list, so a stale address
    # gaining sign-off over a whole show is visible. +area_scope+ qualifies an
    # out-of-scope area, which a blank Area cell reaches with no re-home.
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

    def absent_budgets
      named = @entries.filter_map { |entry| entry.budget&.record_id }.to_set
      @existing_budgets.reject { |budget| named.include?(budget.record_id) }
    end

    # Absent lines this sheet re-creates inside an area: a stored loose
    # "Cogito: Marketing" against Cogito | Marketing. Two lines, so nothing is
    # merged, but the preview links the two panels. Report, never block.
    def superseded_absent_budgets
      @superseded_absent_budgets ||= absent_budgets.select do |budget|
        creates.any? { |create| supersedes?(create, budget) }
      end
    end

    # [label, count] per DatabaseStore#import_budgets! argument, for the submit
    # button. Keyed by argument (a test pins it) because the button is
    # disabled on an empty count, so a bucket missing here cannot be applied.
    # +re_homes+ is the ticked list.
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

    # Allowed (the overview has a "(none)" bucket), but stated before import.
    def missing_nominal_codes
      @entries.select { |entry| entry.bucket != :invalid && entry.row[:nominal_code].blank? }
    end

    # Canonical TSV for the preview's hidden field. Tabs and newlines in a cell
    # are escaped: an xlsx cell can hold them, and one stray tab would shift
    # every later column when apply re-parses.
    def to_tsv
      ([ TSV_HEADERS.join("\t") ] + @rows.map { |row| tsv_row(row) }).join("\n")
    end

    # Canonical heading => the sheet's heading it was read from (nil if none),
    # stated on the preview so a mis-mapping is visible.
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

    # An unreadable amount is carried on VERBATIM: the blocked preview
    # re-renders from this text and must still show the cell to fix.
    def cell_for(row, field)
      value = row[field]
      case value
      when nil then ""
      when :unreadable then row[:"raw_#{field}"].to_s
      when BigDecimal then value.to_s("F")
      when Array then value.join("; ")
      else value.to_s
      end
    end

    # nil for a wholly blank line, so sheet padding isn't thirty nameless lines.
    def normalize_row(raw)
      @header_for ||= resolve_headers(raw.keys)
      return nil if raw.values.all?(&:blank?)

      raw_amount = cell(raw, :amount)
      amount = parse_amount(raw_amount)
      raw_area_budget = cell(raw, :area_budget)
      area_budget = parse_amount(raw_area_budget)
      {
        area: text(raw, :area).strip.presence,
        # Blank is normal (no agreed total yet). Unreadable BLOCKS the row:
        # read as blank it would create the area with no total and tell nobody.
        area_budget: area_budget,
        name: text(raw, :name).strip,
        nominal_code: cell(raw, :nominal_code).to_s.strip,
        budget_type: normalize_type(cell(raw, :budget_type)),
        amount: amount,
        # Kept only when unreadable, so the error can quote it and a
        # round-tripped row ("£1,200" -> "1200.0") still equals its original.
        raw_amount: (raw_amount.to_s.strip if amount == :unreadable),
        raw_area_budget: (raw_area_budget.to_s.strip if area_budget == :unreadable),
        owner_emails: split_emails(cell(raw, :owner_emails)),
        notes: text(raw, :notes)
      }
    end

    def cell(raw, field)
      raw[header_for[field]]
    end

    def text(raw, field)
      value = cell(raw, field)
      @escaped && TEXT_FIELDS.include?(field) ? unescape_cell(value) : value.to_s
    end

    # --- Which column is which -----------------------------------------------

    def resolve_headers(headers)
      FIELDS.transform_values { |spec| match_header(headers, spec) }
    end

    # Refused rather than resolved: a guess writes the wrong value into a name
    # or a figure with nothing on screen to say so.
    def ambiguous_columns
      header_for.compact.group_by { |_field, header| header }
                .select { |_header, pairs| pairs.size > 1 }
    end

    # Blank stays nil ("no figure given"); anything unreadable becomes
    # :unreadable so the row is flagged rather than imported as nil.
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

    # Two rows that resolved to ONE stored line. #duplicate_rows compares what
    # the sheet typed, so "Marketing" and "Cogito: Marketing" get past it, and
    # applying both would write two forecasts to one budget.
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

      budget, match_error, declined = resolve_budget(row)
      return Entry.new(**base, bucket: :invalid, error: match_error) if match_error

      Entry.new(**base, budget: budget, bucket: bucket_for(row, budget),
                declined_namesakes: declined,
                matched_area_label: matched_area_label(row[:area], budget))
    end

    # [budget, error, declined namesakes] for the stored line this row means.
    # The area-qualified key wins; failing it, the name in either spelling.
    # Several lines under the deciding key block the import: a pick would
    # revise one show's figure against another's line.
    def resolve_budget(row)
      qualified = stored_under(@existing_by_area_and_name,
                               self.class.area_scoped_key(row[:name], row[:area]))
      return [ nil, ambiguous_match_error(row, qualified), [] ] if qualified.size > 1
      return [ qualified.sole, nil, [] ] if qualified.size == 1

      resolve_by_name(row)
    end

    def resolve_by_name(row)
      key = self.class.match_key(row[:name])
      prefixed = stored_under(@existing_by_prefixed_name, key)
      candidates = prefixed | stored_under(@existing_by_bare_name, key)
      return [ candidates.first, nil, [] ] if candidates.size <= 1

      loose = loose_match(row, prefixed, candidates)
      return [ nil, ambiguous_match_error(row, candidates), [] ] unless loose

      [ loose, nil, candidates - [ loose ] ]
    end

    # Of several same-named lines, the one in no area, for a row that named no
    # show: a loose "Marketing" and Cogito's are two lines, and the blank cell
    # is what tells them apart. Not for a row whose cell, or whose prefixed
    # name, already named a show. Where only ONE line answers, #resolve_by_name
    # takes it loose or not, deliberately: a bare sheet must still import.
    def loose_match(row, prefixed, candidates)
      return if row[:area].present? || prefixed.any?

      loose = candidates.select { |budget| budget.area.nil? }
      loose.first if loose.one?
    end

    def stored_under(index, key) = key.nil? ? [] : index.fetch(key, [])

    # At most one answers: #row_error refuses a key several areas share.
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

    # The Area cell tells rows of one name apart; where even that matches,
    # count them rather than list one label twice.
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
        "#{row[:raw_area_budget].inspect} isn't an amount for #{area_label(row)}'s Area total. " \
          "Leave it blank if the total isn't agreed yet."
      elsif row[:area].present? && (areas = colliding_areas(self.class.match_key(row[:area])))
        ambiguous_area_error(row, areas)
      elsif Budget::TYPES.exclude?(row[:budget_type])
        "#{row[:budget_type].inspect} isn't a budget type. Use #{Budget::TYPES.to_sentence(last_word_connector: ' or ')}."
      end
    end

    def duplicate_rows_error(row, twins)
      group = [ row ] + twins
      "The same budget line is named more than once in this sheet " \
        "(#{rows_phrase(group)}). #{duplicate_instruction(group)}"
    end

    # Rows the PREFIX grouped already agree about the area, so advising an Area
    # cell would change nothing.
    def duplicate_instruction(group)
      prefixed = group.find { |row| row[:area].blank? && prefix_area_for(row[:name]) }
      unless prefixed
        return "Name it once: two lines are told apart by their area, not by the name alone."
      end

      "Name it once: #{prefixed[:name].inspect} already names " \
        "#{prefix_area_for(prefixed[:name])}, so an Area cell would not tell them apart."
    end

    def area_label(row)
      row[:area].presence&.inspect || "this line"
    end

    # Area names as first typed, keyed by #match_key, so a later "cogito "
    # doesn't change the casing the store is handed.
    def first_seen_names
      @first_seen_names ||= (@entries - entries_in(:invalid)).each_with_object({}) do |entry, names|
        next if entry.area_name.blank?

        names[self.class.match_key(entry.area_name)] ||= entry.area_name
      end
    end

    # #match_key(area name) => the distinct Area totals the sheet gives it,
    # first seen first.
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
        @errors << "#{conflict[:area_name].inspect} has more than one Area total figure in " \
                   "this sheet (#{amounts}). Make every line for the area agree, or leave the " \
                   "column blank."
      end
    end

    # Area's uniqueness check runs under utf8mb4_unicode_ci, which folds
    # accents; #match_key does not. Unchecked, "Cógito" beside "Cogito" reaches
    # Area.create! and 500s inside apply's transaction, losing the paste. New
    # areas are checked against each other too. transliterate is broader than
    # the collation, so it can only refuse a name the database would refuse.
    def report_area_collation_clashes
      stored = @existing_areas_by_name.each_value.flat_map { |areas| areas }
                                      .index_by { |area| collation_key(area.name) }
      seen = {}
      area_creates.each do |attrs|
        name = attrs[:name]
        key = collation_key(name)
        clash = stored[key]&.name || seen[key]
        if clash
          @errors << "#{name.inspect} and #{clash.inspect} are the same area name as far as " \
                     "the database is concerned, which ignores accents. Spell the area one way."
        else
          seen[key] = name
        end
      end
    end

    def collation_key(name) = ActiveSupport::Inflector.transliterate(self.class.match_key(name))

    # grouping key => { area:, area_name:, owner_ids: } for each area the owner
    # column feeds. Keyed by record id where the area exists, so lines reaching
    # it by cell or by a blank cell merge, else by name.
    def owner_targets
      @owner_targets ||= (@entries - entries_in(:invalid)).each_with_object({}) do |entry, targets|
        next if entry.owner_ids.empty?

        area, key, name = resolve_owner_target(entry)
        next if key.nil?

        target = (targets[key] ||= { area: area, area_name: name, owner_ids: [] })
        target[:owner_ids] |= entry.owner_ids
      end
    end

    # [area or nil, grouping key, area name] for the area a line's owners go
    # to: the one the sheet names, else the budget's own. Empty for a line in
    # no area, whose owners stay on the budget.
    def resolve_owner_target(entry)
      name = create_area_name(entry)
      if name.present?
        key = self.class.match_key(name)
        existing = existing_area_for(key)
        [ existing, target_key(existing, key), first_seen_names[key] || name ]
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

    # Whether the area will name somebody after this import. An address that
    # matched nobody adds nobody.
    def area_will_have_owners?(area, name_key)
      return true if area&.owners&.any?

      owner_targets[target_key(area, name_key)].present?
    end

    # Only where the absent line's own name carries the create's area as a
    # prefix: a show's "Marketing" beside a standing one is a legitimate pair.
    def supersedes?(create, budget)
      area = create[:area_name] || @existing_areas_by_id[create[:area_id]]&.name
      return false if area.blank?

      bare = self.class.bare_name(budget.name, area)
      return false if bare == budget.name

      self.class.match_key(bare) == self.class.match_key(create[:name])
    end

    def area_attrs_for(entry) = area_attrs_for_name(entry.area_name)

    def area_attrs_for_name(name)
      return {} if name.blank?

      existing = existing_area_for(self.class.match_key(name))
      existing ? { area_id: existing.record_id } : { area_name: name }
    end

    def re_home_for(entry, key, current, existing)
      { budget_id: entry.budget.record_id, budget_name: entry.budget.name,
        from_area_name: current&.name, from_area_scope: out_of_scope_label(current),
        to_area_name: first_seen_names[key], to_area_is_new: existing.nil?,
        # Read after this import's own owner column, or a sheet naming an owner
        # for the target area would warn falsely.
        to_area_has_owners: area_will_have_owners?(existing, key),
        key: entry.budget.record_id }.merge(area_attrs_for(entry))
    end

    # Why +area+ is outside this import's year and centre, so a
    # "Cogito -> Cogito" label says which. nil for an ordinary re-home.
    def out_of_scope_label(area)
      return if area.nil? || @existing_areas_by_id.key?(area.record_id)

      parts = []
      parts << area.financial_year.label if area.financial_year && area.financial_year_id != financial_year&.id
      parts << area.cost_centre.name if area.cost_centre && area.cost_centre_id != cost_centre&.id
      parts.join(", ").presence
    end

    def row_key(index)
      @row_keys ||= {}
      return @row_keys[index] if @row_keys.key?(index)

      row = @rows[index]
      @row_keys[index] =
        if row[:name].blank?
          nil
        else
          self.class.area_scoped_key(row[:name], row[:area].presence || prefix_area_for(row[:name])) ||
            [ nil, self.class.match_key(row[:name]) ]
        end
    end

    # The area a row's NAME points at, where its cell is blank and the sheet
    # names that area elsewhere: "Cogito: Marketing" beside a Cogito row is one
    # line written twice. It normalises the row's single key and never adds a
    # second, so #duplicate_rows stays an equivalence.
    def prefix_area_for(name)
      sheet_area_names.find { |area| self.class.bare_name(name, area) != name.to_s }
    end

    def sheet_area_names
      @sheet_area_names ||= @rows.filter_map { |row| row[:area].presence }
                                 .uniq { |name| self.class.match_key(name) }
    end

    # The area a row lands in: its cell, or for a create with a blank cell the
    # area its name prefixes, on #row_key's terms. Grouping and creating must agree, or the next
    # converted sheet creates the line again inside the area. A MATCHED row
    # keeps its cell: moving a stored line on a prefix is a bigger claim. In
    # first-seen casing, so "cogito" cannot mint a second area.
    def create_area_name(entry)
      return entry.area_name if entry.area_name.present?
      return unless entry.budget.nil?

      prefix = prefix_area_for(entry.row[:name])
      prefix && (first_seen_names[self.class.match_key(prefix)] || prefix)
    end

    # The matched line's area where it differs from the row's cell, nil when
    # they agree. Compared by RECORD, as #re_homes is, and qualified by year
    # and centre only where the names match but the records don't.
    def matched_area_label(area_name, budget)
      # An unmatched row reports nothing, or the first import of a year says
      # "matched: no area" on every row.
      return if budget.nil?

      matched = budget.area
      typed = area_name.presence
      return if typed.nil? && matched.nil?
      return "no area" if matched.nil?
      return matched.name if typed.nil? || self.class.match_key(typed) != self.class.match_key(matched.name)
      return if existing_area_for(self.class.match_key(typed))&.record_id == matched.record_id

      self.class.area_label(matched)
    end

    # Row index => the other rows naming the same line. A row that names an
    # area (by cell or prefix) is identified BY that area, so "Marketing" under
    # Cogito and under nothing are two lines.
    def duplicate_rows
      groups = Hash.new { |index, key| index[key] = [] }
      @rows.each_index do |index|
        groups[row_key(index)] << index unless row_key(index).nil?
      end

      @rows.each_index.to_h do |index|
        twins = row_key(index).nil? ? [] : groups[row_key(index)] - [ index ]
        [ index, twins.map { |other| @rows[other] } ]
      end
    end

    # Person ids for the sheet's owner emails, plus the addresses that matched
    # nobody. Never creates a Person from a bare email.
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
