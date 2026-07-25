module Reimbursements
  ##
  # A subtotal presenter for the budget overview: one nominal code and the
  # budgets filed under it, exposing each overview metric as the sum of the
  # group's budgets. A budget's nil figure (e.g. no projected amount) counts as
  # zero so a partly-planned group still totals cleanly. Reused for the
  # grand-total footer by passing every budget with a nil code.
  #
  # Expense and Income budgets are never added together. A group can hold both
  # (nothing stops two budgets of different types sharing a nominal code), so
  # every total the page shows comes from #by_type: one subtotal per type
  # present, each tagged with the type it covers. Adding the two would produce a
  # figure that is neither total spend nor net, since £10k of spend plus £8k of
  # income is not £18k of anything.
  NominalCodeRollup = Struct.new(:code, :budgets, :budget_type) do
    def initial     = sum_of(&:initial_budget)
    def projected   = sum_of(&:projected_amount)
    def committed   = sum_of(&:committed_amount)
    def pipeline    = sum_of(&:pipeline_amount)
    def paid_portal = sum_of(&:paid_portal_amount)
    def eusa_actual = sum_of(&:eusa_actual_amount)

    # Blank for an income subtotal, mirroring Budget#expected_outturn: "the
    # greater of the projection and what's already been spent" is a worst-case
    # cost, and the same max over income lines reads as best-case income — the
    # opposite direction from what the column's tooltip promises.
    def expected = income? ? nil : sum_of(&:expected_outturn)

    def income? = budget_type == "Income"

    # This group split into one subtotal per budget type present, in
    # Budget::TYPES order. A type with no budgets in the group is omitted rather
    # than shown as a row of zeroes.
    def by_type
      Budget::TYPES.filter_map do |type|
        of_type = budgets.select { |budget| budget.budget_type == type }
        self.class.new(code, of_type, type) if of_type.any?
      end
    end

    # The group's budgets in display order, the order the page lists them in
    # under their nominal-code heading.
    def rows = budgets.sort_by { |budget| budget.name.to_s.downcase }

    private

    def sum_of(&block)
      budgets.sum { |budget| block.call(budget) || 0 }
    end
  end
end
