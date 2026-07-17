module Reimbursements
  ##
  # Budget-owner review gate helpers. A budget's owners must sign off on an
  # expense charged to their budget before finance can approve it — unless the
  # submitter is themselves an owner (auto-bypass) or the budget has no owners.
  # The pure predicates operate on Airtable POROs; +gate_satisfied?+ also
  # consults the OwnerEndorsement table.
  module OwnerReview
    module_function

    # Budgets the given person owns (nil person owns nothing).
    def owned_budgets(budgets, person)
      return [] if person.nil?

      budgets.select { |budget| budget.owner_ids.include?(person.record_id) }
    end

    # Does the given person own the budget this expense is charged to?
    def owned_by?(expense, person)
      return false if person.nil? || expense.budget.nil?

      expense.budget.owner_ids.include?(person.record_id)
    end

    # The submitter is among the budget's owners — so their own claim needs no
    # separate endorsement.
    def submitter_owns_budget?(expense)
      return false if expense.person.nil?

      owned_by?(expense, expense.person)
    end

    # Does this expense need a budget owner's endorsement before finance can
    # approve it? True only when the budget has owners AND the submitter isn't
    # one of them.
    def gate_applies?(expense)
      budget = expense.budget
      return false if budget.nil? || budget.owner_ids.empty?

      !submitter_owns_budget?(expense)
    end

    # Is the owner gate satisfied for this expense? Satisfied when the gate
    # doesn't apply, or an endorsement / finance override row exists.
    def gate_satisfied?(expense)
      return true unless gate_applies?(expense)

      OwnerEndorsement.for_expense(expense.record_id).exists?
    end
  end
end
