module Reimbursements
  ##
  # One-off: fills each cost centre's nominal code list from the codes its
  # budgets already carry (bin/rails reimbursements:nominal_code_seed).
  module NominalCodeSeed
    # What #apply! would write: one entry per (cost centre, code) not yet listed.
    # +label+ is a guess (the commonest budget name behind the code) for finance
    # to correct. +unplaced_count+ says how many budgets had no centre and were
    # folded into the default one.
    def self.plan
      budgets = Budget.where.not(nominal_code: "").order(:id).to_a
      groups = budgets.group_by { |b| [ effective_cost_centre_id(b), b.nominal_code ] }
      return [] if groups.empty?

      centres = CostCentre.where(id: groups.keys.map(&:first).compact.uniq).index_by(&:id)

      taken = taken_labels(groups.keys.filter_map(&:first).uniq)

      groups.filter_map do |(cost_centre_id, code), group_budgets|
        next if cost_centre_id.nil? # no default centre to fold an unplaced code into
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

    # Idempotent: a listed code is never re-created or relabelled.
    def self.apply!
      plan.each do |entry|
        NominalCode.find_or_create_by!(cost_centre: entry[:cost_centre], code: entry[:code]) do |nominal_code|
          nominal_code.label = entry[:label]
        end
      end
    end

    # An unplaced budget's code goes to the DEFAULT centre: seeding it into every
    # centre would invent accounts, and into none would lose it.
    def self.effective_cost_centre_id(budget)
      budget.cost_centre_id || CostCentre.default&.id
    end
    private_class_method :effective_cost_centre_id

    # The commonest name; a tie goes to the lowest budget id (#plan orders by id).
    def self.derive_label(budgets)
      budgets.map(&:name).tally.max_by { |_name, count| count }.first
    end
    private_class_method :derive_label

    # Labels are unique per centre, so a clash is qualified with the code rather
    # than refused: refusing would abort the seed over the committee's own data.
    def self.unique_label(derived, code, taken)
      candidate = derived
      # The extra suffix cannot be a space: match_key strips those, so the loop
      # would never end.
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

    # Labels already held in each centre, including by codes #plan skips.
    def self.taken_labels(cost_centre_ids)
      existing = NominalCode.where(cost_centre_id: cost_centre_ids).pluck(:cost_centre_id, :label)
      cost_centre_ids.index_with do |id|
        existing.filter_map { |centre_id, label| key(label) if centre_id == id }.to_set
      end
    end
    private_class_method :taken_labels

    # Compared as utf8mb4_unicode_ci does, or apply! gets a pair the database refuses.
    def self.key(label) = BudgetImport.match_key(label)
    private_class_method :key
  end
end
