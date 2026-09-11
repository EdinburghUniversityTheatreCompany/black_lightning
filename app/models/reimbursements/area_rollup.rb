module Reimbursements
  ##
  # A subtotal presenter for the budget overview's area card: one area and the
  # budgets filed under it, totalled through RollupTotals exactly as the
  # nominal-code card totals its groups. The unassigned group is this object
  # with a nil area.
  #
  # Keyword-built, unlike NominalCodeRollup: its members are three collaborators
  # of the same shape, and a positional (area, budgets, budget_type) invites an
  # argument-order slip at every call site.
  #
  # The money columns cover the budgets HANDED IN — the ones the screen's year
  # and cost centre scope to. #agreed and #unallocated instead come off the area
  # itself, whose own figures (Area#projected_amount, #allocated) sum every line
  # ever linked to it, in any year or centre. A budget CAN hold an area from
  # another year (an ordinary update writes it, and the budget form preserves
  # such a row deliberately), so the two readings can disagree: #lines_shown
  # against #lines_total is what makes that visible instead of silently dropping
  # the out-of-scope spend or silently counting it.
  AreaRollup = Struct.new(:area, :budgets, :budget_type, keyword_init: true) do
    include RollupTotals

    def name = area&.name

    # The committee's agreed figure for the whole area, nil when nobody agreed
    # one — never zero, which would read as the area being fully overspent.
    def agreed = area&.projected_amount

    # The part of that agreed total not yet split out into category lines. NOT
    # spare money, and nil for the same reason #agreed is.
    def unallocated = area&.unallocated

    # Lines on screen against every line the area holds. Read these off the
    # GROUP rollup: a #by_type child holds one type's slice, so its counts
    # describe that slice rather than the area's place in the page's scope.
    #
    # area.budgets is preloaded by store.areas, so .size reads the loaded array
    # rather than issuing a COUNT per area.
    def lines_shown = budgets.size
    def lines_total = area ? area.budgets.size : budgets.size
    def lines_out_of_scope = lines_total - lines_shown

    private

    def with_budgets(budgets, type) = self.class.new(area: area, budgets: budgets, budget_type: type)
  end
end
