module Reimbursements
  ##
  # Budget health flags shared by the ActiveRecord Budget and the
  # Airtable-era PORO — the over-budget badge logic was re-litigated once
  # already (a red badge next to a positive Remaining), so both backends must
  # keep answering it identically. Includers provide budget_type, remaining,
  # initial_budget, committed_amount and total_paid.
  module BudgetHealth
    def income? = budget_type == "Income"

    # Genuinely overspent: nothing left against the current forecast/plan.
    # `remaining` already folds in forecast, committed and paid, so the badge
    # keys off it alone. Nil means "not tracked"; income budgets are never
    # over budget.
    def over_budget?
      return false if income?

      !remaining.nil? && remaining.negative?
    end

    # A softer state: committed or paid has passed the ORIGINAL initial
    # figure, but the forecast was revised up to cover it so there's still
    # remaining. Worth flagging (the plan grew) but not the same alarm as
    # over_budget?.
    def over_initial_budget?
      return false if income? || over_budget?
      return true if initial_budget && committed_amount && committed_amount > initial_budget
      return true if initial_budget && total_paid && total_paid > initial_budget

      false
    end
  end
end
