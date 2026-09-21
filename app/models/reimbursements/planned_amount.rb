module Reimbursements
  ##
  # Whether anybody has actually set a figure for this budget line or area.
  #
  # Nil is the obvious case. EXACTLY ZERO is the one this module exists for:
  # production carries many termtime areas whose agreed total is £0 and which
  # have real spend against them, and reading that 0 as a CAP made every one of
  # them "over budget" in red — a permanent false alarm, which is how a real one
  # stops being read. A 0 there is a figure nobody filled in, not a promise to
  # spend nothing (Mick's call).
  #
  # ONE predicate, included by both Budget and Area, because the coming area
  # page needs the same reading and two copies of a rule this quiet would drift.
  #
  # The includer supplies +projected_amount+ (its current plan: the latest
  # forecast, else the initial figure).
  module PlannedAmount
    def no_budget_set?
      plan = projected_amount
      return true if plan.nil?

      plan.zero? && nothing_allocated?
    end

    # A budget LINE has no sub-lines to allocate to, so a zero plan on one is
    # simply unset. Area overrides this: a £0 total with lines allocated under
    # it is contradicted by those lines, and that disagreement is worth showing
    # rather than hiding behind "no budget set".
    def nothing_allocated?
      true
    end
  end
end
