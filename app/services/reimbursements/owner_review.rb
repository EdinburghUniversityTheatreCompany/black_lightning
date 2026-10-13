module Reimbursements
  ##
  # The budget-owner sign-off gate: an owner endorses a claim before finance
  # approves it, unless the submitter is an owner or the budget has none.
  module OwnerReview
    module_function

    def owned_budgets(budgets, person)
      return [] if person.nil?

      budgets.select { |budget| budget.owner_ids.include?(person.record_id) }
    end

    def owned_by?(expense, person)
      return false if person.nil? || expense.budget.nil?

      expense.budget.owner_ids.include?(person.record_id)
    end

    # A submitter who owns the budget needs no separate endorsement.
    def submitter_owns_budget?(expense) = owned_by?(expense, expense.person)

    def gate_applies?(expense)
      budget = expense.budget
      return false if budget.nil? || budget.owner_ids.empty?

      !submitter_owns_budget?(expense)
    end

    def gate_satisfied?(expense)
      return true unless gate_applies?(expense)

      endorsement_covers?(OwnerEndorsement.for_expense(expense.record_id).first, expense)
    end

    # A Set of the record ids whose gate is unmet, in one endorsement query.
    def unmet_gate_expense_ids(expenses)
      gated = expenses.select { |expense| gate_applies?(expense) }
      return Set.new if gated.empty?

      by_expense = OwnerEndorsement.where(expense_record_id: gated.map(&:record_id))
                                   .index_by(&:expense_record_id)
      gated.reject { |expense| endorsement_covers?(by_expense[expense.record_id], expense) }
           .map(&:record_id).to_set
    end

    # The Review queue's tabs, and the finance home's counts: the Pending claims split by
    # whether their owner gate is unmet, plus the Approved ones. +unmet_ids+ is returned too,
    # since the cards mark a gated claim. One split, so the screens cannot disagree on whose
    # queue a claim is in.
    def split_queue(expenses)
      pending = expenses.select(&:pending?)
      unmet = unmet_gate_expense_ids(pending)
      awaiting_owner, to_approve = pending.partition { |expense| unmet.include?(expense.record_id) }
      { pending: pending, unmet_ids: unmet,
        approved: expenses.select { |expense| expense.status == Status::APPROVED },
        awaiting_owner: awaiting_owner, to_approve: to_approve }
    end

    # A sign-off covers one budget and amount, so editing either re-opens the gate.
    def endorsement_covers?(endorsement, expense)
      return false if endorsement.nil?

      endorsement.budget_record_id == expense.budget&.record_id &&
        endorsement.endorsed_amount == expense.amount
    end
  end
end
