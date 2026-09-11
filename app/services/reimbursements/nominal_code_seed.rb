module Reimbursements
  ##
  # One-off: populate each cost centre's nominal code list from the codes its
  # budgets already carry. NominalCode is new (see NominalCode) and starts
  # empty; this is what fills it the first time, from history rather than a
  # blank form.
  #
  # A SERVICE rather than migration code, because test and CI databases are
  # schema-loaded, so a data migration never runs there and could never be
  # tested — the same reason AreaBackfill and AreaRename are this shape.
  #
  # Reads Budget directly rather than through Reimbursements.build_store: the
  # store's #budgets is scoped to one cost centre / financial year at a time
  # (built for a request), while this needs every budget across every centre
  # in a single pass, the same reason AreaBackfill reads Budget.all.
  module NominalCodeSeed
    # What #apply! would write, without writing it: one entry per (cost
    # centre, code) pair not already listed, in the shape
    # { cost_centre:, code:, label:, budget_count:, unplaced_count: }.
    #
    # +label+ is a GUESS — the most common name among the budgets carrying
    # that code — for finance to correct once it's on a screen (Task 3);
    # never invented from nothing.
    #
    # +unplaced_count+ names how many of +budget_count+ came from a budget
    # with NO cost centre of its own. Those fold into the DEFAULT centre's
    # entry (see #effective_cost_centre_id) rather than every centre's or
    # none's, the same rule #expenses_owned_by_cost_centre applies to money —
    # and is broken out here rather than left inside the total so finance can
    # see what it inherited instead of discovering it.
    def self.plan
      budgets = Budget.where.not(nominal_code: "").order(:id).to_a
      groups = budgets.group_by { |b| [ effective_cost_centre_id(b), b.nominal_code ] }
      return [] if groups.empty?

      centres = CostCentre.where(id: groups.keys.map(&:first).compact.uniq).index_by(&:id)

      taken = taken_labels(groups.keys.filter_map(&:first).uniq)

      groups.filter_map do |(cost_centre_id, code), group_budgets|
        next if cost_centre_id.nil? # no default centre configured — nowhere to seed an unplaced code
        next if NominalCode.exists?(cost_centre_id: cost_centre_id, code: code)

        derived = derive_label(group_budgets)
        label = unique_label(derived, code, taken[cost_centre_id])
        {
          cost_centre: centres.fetch(cost_centre_id),
          code: code,
          label: label,
          label_disambiguated: label != derived,
          budget_count: group_budgets.size,
          unplaced_count: group_budgets.count { |b| b.cost_centre_id.nil? }
        }
      end.sort_by { |entry| [ entry[:cost_centre].name, entry[:code] ] }
    end

    # Writes #plan. Idempotent: a code #plan already excludes (because
    # NominalCode.exists? found it) is never re-created, so running this
    # twice — or after a human has since edited a seeded label — changes
    # nothing the second time.
    def self.apply!
      plan.each do |entry|
        NominalCode.find_or_create_by!(cost_centre: entry[:cost_centre], code: entry[:code]) do |nominal_code|
          nominal_code.label = entry[:label]
        end
      end
    end

    # A budget with no cost centre of its own is lenient-scoped into EVERY
    # centre's screens (DatabaseStore#in_cost_centre) — but seeding its code
    # into every centre would invent accounts that centre never had, and
    # seeding it into none would lose the code entirely. Falls to the DEFAULT
    # centre instead, matching #expenses_owned_by_cost_centre's rule for the
    # same shape of gap.
    def self.effective_cost_centre_id(budget)
      budget.cost_centre_id || CostCentre.default&.id
    end
    private_class_method :effective_cost_centre_id

    # The name most of the group's budgets share, ties broken by whichever
    # sorts first among the group's own ids (the query above is ordered by
    # id, so #tally sees them in that order and #max_by keeps the first tied
    # winner it encounters) — deterministic without inventing a preference the
    # data doesn't state.
    def self.derive_label(budgets)
      budgets.map(&:name).tally.max_by { |_name, count| count }.first
    end
    private_class_method :derive_label

    # Two codes whose budgets share a common name derive the SAME label, and a
    # centre's labels are unique (NominalCode) because BudgetFinder matches a
    # hand-named line by label — two codes answering to one would adopt the
    # same uncoded line and leave the second code unopenable for ever.
    #
    # So the collision is qualified rather than refused: the label is already
    # an explicit guess finance corrects on the cost centre's settings page,
    # and a guess that names its own code is still one. Refusing instead would
    # abort the whole seed over data the committee has every right to have.
    def self.unique_label(derived, code, taken)
      candidate = derived
      # The code is the one thing guaranteed distinct here, so it is what the
      # qualifier carries. A numeric suffix beyond that only runs if a centre
      # already holds that exact qualified label; it cannot be a space, since
      # match_key strips and squeezes those and the loop would never end.
      candidate = "#{derived} (#{code})" if taken.include?(key(candidate))
      suffix = 2
      while taken.include?(key(candidate))
        candidate = "#{derived} (#{code}) #{suffix}"
        suffix += 1
      end
      taken << key(candidate)
      candidate
    end
    private_class_method :unique_label

    # Labels already spoken for in each centre — the rows #plan skips because
    # their code is seeded, which still hold their names.
    def self.taken_labels(cost_centre_ids)
      existing = NominalCode.where(cost_centre_id: cost_centre_ids).pluck(:cost_centre_id, :label)
      cost_centre_ids.index_with do |id|
        existing.filter_map { |centre_id, label| key(label) if centre_id == id }.to_set
      end
    end
    private_class_method :taken_labels

    # NominalCode compares labels case-insensitively under utf8mb4_unicode_ci,
    # so the plan has to reserve them the same way or it hands apply! a pair
    # the database then refuses.
    def self.key(label) = BudgetImport.match_key(label)
    private_class_method :key
  end
end
