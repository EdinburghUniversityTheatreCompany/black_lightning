module Reimbursements
  ##
  # Whether anybody has actually set a figure for this budget line or area.
  #
  # Nil is the obvious case. EXACTLY ZERO is what this module exists for:
  # production has many termtime areas with a £0 agreed total and real spend, and
  # reading that 0 as a CAP painted every one over budget in red, a permanent
  # false alarm that hides a real one. A 0 there is a figure nobody filled in.
  #
  # ONE predicate, included by both Budget and Area, because two copies of a rule
  # this quiet would drift. The includer supplies +projected_amount+ (the latest
  # forecast, else the initial figure).
  module PlannedAmount
    def no_budget_set?
      plan = projected_amount
      return true if plan.nil?

      plan.zero? && nothing_allocated?
    end

    # A budget LINE has no sub-lines, so a zero plan on one is simply unset. Area
    # overrides this: lines allocated under a £0 total contradict it, and that
    # is worth showing rather than hiding behind "no budget set".
    def nothing_allocated?
      true
    end
  end
end
