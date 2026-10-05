module Reimbursements
  ##
  # Budget health flags, in one place because the badge was once got wrong (red
  # beside a positive Remaining). Includers provide budget_type, remaining,
  # initial_budget, committed_amount and total_paid.
  module BudgetHealth
    def income? = budget_type == "Income"

    # Overspent against the plan. A nil remaining is untracked; income is never
    # over budget.
    def over_budget?
      return false if income?

      !remaining.nil? && remaining.negative?
    end

    # Softer: spend passed the ORIGINAL initial figure, but a raised forecast
    # still covers it.
    def over_initial_budget?
      return false if income? || over_budget?
      return true if initial_budget && committed_amount && committed_amount > initial_budget
      return true if initial_budget && total_paid && total_paid > initial_budget

      false
    end
  end
end
