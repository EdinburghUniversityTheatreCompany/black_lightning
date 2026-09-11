module Reimbursements
  ##
  # A subtotal presenter for the budget overview's area card: one area and the
  # budgets filed under it, totalled through RollupTotals exactly as the
  # nominal-code card totals its groups. The unassigned group is this object
  # with a nil area.
  #
  # The money columns cover the budgets HANDED IN — the ones the screen's year
  # and cost centre scope to — while #agreed and #unallocated come off the area
  # itself, which sums every line ever linked to it in any year or centre. A
  # budget CAN hold an area from another year, so the two readings disagree,
  # and #lines_shown against #lines_total is what makes that visible rather
  # than silently dropping or silently counting the out-of-scope spend.
  AreaRollup = Struct.new(:area, :budgets, :budget_type, keyword_init: true) do
    include RollupTotals

    def name = area&.name

    # Nil when nobody agreed one — never zero, which reads as fully overspent.
    def agreed = area&.projected_amount

    # NOT spare money, and nil for the same reason #agreed is. Summed on the
    # area's declared basis (Area#allocated), which is why an area holding both
    # budget types has a defensible figure at all — Phase 2a withheld it,
    # having no declared basis to read.
    def unallocated = area&.unallocated

    # In the words the area's own form offered. The unassigned group has no
    # area and names nothing, exactly as it reports no agreed total.
    def total_label = area&.basis_label

    # Read off the GROUP rollup, which is what makes #with_budgets drop the
    # area: a #by_type child holds one TYPE's slice while the area's own counts
    # cover both, so a child inheriting the area answered a lines_total the
    # rows beneath it do not add up to. area.budgets is preloaded by
    # store.areas, so .size reads the loaded array rather than a COUNT per area.
    def lines_shown = budgets.size
    def lines_total = area ? area.budgets.size : budgets.size
    def lines_out_of_scope = lines_total - lines_shown

    private

    # No area, deliberately, and it is what keeps the basis out of #by_type:
    # every area figure on a per-type subtotal then answers nil (or 0 for the
    # counts), which reads as "ask the group, not me", where the parent's
    # number reads as a fact about a row it does not describe. The view builds
    # a subtotal's label from the group's own, never from #name.
    def with_budgets(budgets, type) = self.class.new(area: nil, budgets: budgets, budget_type: type)
  end
end
