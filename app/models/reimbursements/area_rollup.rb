module Reimbursements
  ##
  # The budget overview's area card: one area and the budgets filed under it,
  # totalled through RollupTotals as the nominal-code card totals its groups. The
  # unassigned group is this object with a nil area.
  #
  # The money columns cover the budgets HANDED IN (the screen's year and cost
  # centre), while #agreed and #unallocated come off the area, which sums every
  # line ever linked to it. A budget can hold an area from another year, so the
  # two disagree, and #lines_shown against #lines_total makes that visible.
  AreaRollup = Struct.new(:area, :budgets, :budget_type, keyword_init: true) do
    include RollupTotals

    def name = area&.name

    # Nil when nobody agreed one, never zero, which reads as fully overspent.
    def agreed = area&.projected_amount

    # Whether that total is one nobody set: absent, or a £0 with nothing allocated
    # (see PlannedAmount). The card then suppresses the figure, since "Agreed
    # total (expenses) £0.00" reads as a claim about expenses. The unassigned
    # group agrees nothing either.
    def no_budget_set? = area.nil? || area.no_budget_set?

    # NOT spare money, and nil for the same reason as #agreed. On the area's
    # declared basis (Area#allocated).
    def unallocated = area&.unallocated

    # In the words the area's own form offered; the unassigned group names nothing.
    def total_label = area&.basis_label

    # Read off the GROUP rollup, which is why #with_budgets drops the area: a
    # #by_type child holds one type's slice, so inheriting the area's counts would
    # give a lines_total its rows do not add up to. area.budgets is preloaded by
    # store.areas, so .size reads the loaded array rather than a COUNT per area.
    def lines_shown = budgets.size
    def lines_total = area ? area.budgets.size : budgets.size
    def lines_out_of_scope = lines_total - lines_shown

    private

    # No area, and that keeps the basis out of #by_type: area figures on a
    # per-type subtotal answer nil (0 for the counts), reading as "ask the group",
    # where the parent's number would read as a fact about a row it does not
    # describe. The view labels a subtotal from the group's own label.
    def with_budgets(budgets, type) = self.class.new(area: nil, budgets: budgets, budget_type: type)
  end
end
