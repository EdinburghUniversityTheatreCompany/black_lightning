module Reimbursements
  ##
  # A subtotal presenter for the budget overview's area card: one area and the
  # budgets filed under it, totalled through RollupTotals exactly as the
  # nominal-code card totals its groups. The unassigned group is this object
  # with a nil area.
  #
  # The money columns cover the budgets HANDED IN — the ones the screen's year
  # and cost centre scope to. #agreed and #unallocated instead come off the area
  # itself, whose figures sum every line ever linked to it, in any year or
  # centre. A budget CAN hold an area from another year, so the two readings can
  # disagree: #lines_shown against #lines_total is what makes that visible
  # rather than silently dropping or silently counting the out-of-scope spend.
  AreaRollup = Struct.new(:area, :budgets, :budget_type, keyword_init: true) do
    include RollupTotals

    def name = area&.name

    # The committee's agreed figure for the whole area, nil when nobody agreed
    # one — never zero, which would read as the area being fully overspent.
    def agreed = area&.projected_amount

    # The part of that agreed total not yet split out into category lines. NOT
    # spare money, and nil for the same reason #agreed is.
    #
    # Withheld entirely for an area holding both budget types: Area#unallocated
    # subtracts every line's projection with no type filter, so £1,000 agreed
    # over £400 of spend and £800 of income prints -£200 — indistinguishable
    # from real over-allocation, and the one figure here that would net income
    # against spend.
    def unallocated
      return nil if mixed_budget_types?

      area&.unallocated
    end

    # Read against EVERY line the area holds, not the ones on screen: the figure
    # this guards is summed over all of them too.
    def mixed_budget_types?
      return false if area.nil?

      area.budgets.map(&:budget_type).uniq.size > 1
    end

    # Read off the GROUP rollup: a #by_type child holds one type's slice, so its
    # counts describe that slice rather than the area's place in the page's
    # scope. area.budgets is preloaded by store.areas, so .size reads the loaded
    # array rather than a COUNT per area.
    def lines_shown = budgets.size
    def lines_total = area ? area.budgets.size : budgets.size
    def lines_out_of_scope = lines_total - lines_shown

    private

    def with_budgets(budgets, type) = self.class.new(area: area, budgets: budgets, budget_type: type)
  end
end
