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
  # centre.
  #
  # The area's budget basis reaches #unallocated and #total_label and stops
  # there: #by_type keeps its two separate subtotals on BOTH bases, because
  # "what did this area spend" is a different question from "how much room has
  # it left" and only the second one ever nets income against spend.
  #
  # A budget CAN hold an area from another year, so the two readings can
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
    # Summed on the area's declared basis (Area#allocated), so an area holding
    # both budget types has a defensible figure either way: a spend cap leaves
    # its income lines out, a net allowance credits them. Phase 2a withheld
    # this figure for such an area because there was no declared basis to read
    # and netting was the only arithmetic on offer.
    def unallocated = area&.unallocated

    # What that agreed total is a total OF, in the words the area's own form
    # offered. The unassigned group has no area and so names nothing, exactly
    # as it reports no agreed total.
    def total_label = area&.basis_label

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
