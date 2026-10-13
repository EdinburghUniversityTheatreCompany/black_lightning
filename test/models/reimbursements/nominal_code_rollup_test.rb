require "test_helper"

module Reimbursements
  # The overview's per-nominal-code subtotal. The RollupTotals sums it shares with
  # AreaRollup are pinned in area_rollup_test.rb.
  class NominalCodeRollupTest < ActiveSupport::TestCase
    def build_budget(**attrs)
      Budget.create!(name: "B", **attrs)
    end

    test "by_type splits a mixed group so spend and income are never added up" do
      spend = build_budget(nominal_code: "4000", initial_budget: 10_000)
      income = build_budget(nominal_code: "4000", budget_type: "Income", initial_budget: 8000)

      subtotals = NominalCodeRollup.new("4000", [ spend, income ]).by_type

      assert_equal %w[Expense Income], subtotals.map(&:budget_type)
      assert_equal BigDecimal("10000"), subtotals.first.initial
      assert_equal BigDecimal("8000"), subtotals.last.initial
      assert subtotals.all? { |s| s.budgets.all? { |b| b.budget_type == s.budget_type } }
    end
  end
end
