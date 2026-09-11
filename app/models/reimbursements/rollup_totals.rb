module Reimbursements
  ##
  # The arithmetic the budget overview's two rollups share: each column is the
  # sum of a group of budgets, with a budget's nil figure counting as zero so a
  # partly-planned group still totals cleanly.
  #
  # The two groupings are different axes over the SAME budgets — EUSA's nominal
  # code and Bedlam's areas — so the columns have to be summed identically or
  # the two cards on one page would disagree about the same money.
  #
  # An includer supplies +budgets+, +budget_type+ and a private #with_budgets
  # building a sibling rollup for one type.
  module RollupTotals
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
    # than shown as a row of zeroes. Expense and Income are never added
    # together: £10k of spend plus £8k of income is not £18k of anything.
    def by_type
      Budget::TYPES.filter_map do |type|
        of_type = budgets.select { |budget| budget.budget_type == type }
        with_budgets(of_type, type) if of_type.any?
      end
    end

    # The group's budgets in display order, the order the page lists them in
    # under their heading.
    def rows = budgets.sort_by { |budget| budget.name.to_s.downcase }

    private

    def sum_of(&block)
      budgets.sum { |budget| block.call(budget) || 0 }
    end
  end
end
