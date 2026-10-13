module Reimbursements
  ##
  # The sums the overview's nominal-code and area rollups share, so the two
  # cards cannot disagree about the same money. A nil figure counts as zero.
  # An includer supplies +budgets+, +budget_type+ and a private #with_budgets.
  module RollupTotals
    def initial     = sum_of(&:initial_budget)
    def projected   = sum_of(&:projected_amount)
    def committed   = sum_of(&:committed_amount)
    def pipeline    = sum_of(&:pipeline_amount)
    def paid_portal = sum_of(&:paid_portal_amount)
    def eusa_actual = sum_of(&:eusa_actual_amount)

    def remaining = sum_of(&:remaining)
    def variance  = sum_of(&:variance)

    # Blank for an income subtotal, as Budget#expected_outturn is.
    def expected = income? ? nil : sum_of(&:expected_outturn)

    def income? = budget_type == "Income"

    # One subtotal per type present, in Budget::TYPES order. Expense and
    # Income are never added together.
    def by_type
      Budget::TYPES.filter_map do |type|
        of_type = budgets.select { |budget| budget.budget_type == type }
        with_budgets(of_type, type) if of_type.any?
      end
    end

    # Ordered by the label the rows print (Budget#display_name).
    def rows = budgets.sort_by { |budget| budget.display_name.to_s.downcase }

    private

    def sum_of(&block)
      budgets.sum { |budget| block.call(budget) || 0 }
    end
  end
end
