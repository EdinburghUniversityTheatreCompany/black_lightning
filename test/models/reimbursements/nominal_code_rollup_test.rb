require "test_helper"

module Reimbursements
  # The small presenter that subtotals a group of budgets sharing a nominal
  # code for the overview page — each metric is the sum of the group's budgets,
  # treating a budget's nil figure as zero.
  class NominalCodeRollupTest < ActiveSupport::TestCase
    def build_budget(**attrs)
      Budget.create!(name: "B", **attrs)
    end

    def add_expense(budget, status:, excl_vat:)
      Expense.create!(budget: budget, status: status, amount: excl_vat * 1.2r,
                      amount_excl_vat: excl_vat, description: "x")
    end

    test "sums each metric across the group, treating nil figures as zero" do
      a = build_budget(nominal_code: "4000", initial_budget: 100)
      a.forecasts.create!(amount: 120, date: Date.new(2026, 6, 1), reason: "plan")
      add_expense(a, status: Status::APPROVED, excl_vat: 40)
      add_expense(a, status: Status::PENDING, excl_vat: 15)

      # b has no forecast and no initial budget, so projected is nil (→ 0).
      b = build_budget(nominal_code: "4000")
      add_expense(b, status: Status::PAID, excl_vat: 30)

      rollup = NominalCodeRollup.new("4000", [ Budget.find(a.id), Budget.find(b.id) ])

      assert_equal "4000", rollup.code
      assert_equal BigDecimal("100"), rollup.initial          # b's nil initial → 0
      assert_equal BigDecimal("120"), rollup.projected        # 120 + 0
      assert_equal BigDecimal("70"),  rollup.committed         # 40 + 30
      assert_equal BigDecimal("15"),  rollup.pipeline
      assert_equal BigDecimal("30"),  rollup.paid_portal
      # expected outturn per-budget: a = max(120,40,0,0)=120; b = max(0,30,30,0)=30
      assert_equal BigDecimal("150"), rollup.expected
    end

    test "label reads '(none)' through unchanged and counts its budgets" do
      rollup = NominalCodeRollup.new("(none)", [ build_budget, build_budget ])
      assert_equal "(none)", rollup.code
      assert_equal 2, rollup.budgets.size
    end

    test "by_type splits a mixed group so spend and income are never added up" do
      spend = build_budget(nominal_code: "4000", initial_budget: 10_000)
      income = build_budget(nominal_code: "4000", budget_type: "Income", initial_budget: 8000)

      subtotals = NominalCodeRollup.new("4000", [ spend, income ]).by_type

      assert_equal %w[Expense Income], subtotals.map(&:budget_type)
      assert_equal BigDecimal("10000"), subtotals.first.initial
      assert_equal BigDecimal("8000"), subtotals.last.initial
      # 18,000 is neither total spend nor net, so no rollup reports it.
      assert_empty subtotals.select { |s| s.initial == BigDecimal("18000") }
      assert subtotals.all? { |s| s.budgets.all? { |b| b.budget_type == s.budget_type } }
    end

    test "by_type omits a type with no budgets in the group" do
      only_spend = NominalCodeRollup.new("4000", [ build_budget(nominal_code: "4000") ]).by_type

      assert_equal [ "Expense" ], only_spend.map(&:budget_type)
    end

    test "expected is blank for an income subtotal, summed for an expense one" do
      spend = build_budget(nominal_code: "4000", initial_budget: 250)
      income = build_budget(nominal_code: "8000", budget_type: "Income", initial_budget: 8000)

      expense_rollup, income_rollup =
        NominalCodeRollup.new(nil, [ spend, income ]).by_type

      assert_equal BigDecimal("250"), expense_rollup.expected
      assert_nil income_rollup.expected, "best-case income is not an expected outturn"
    end
  end
end
