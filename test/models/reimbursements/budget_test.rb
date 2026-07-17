require "test_helper"

module Reimbursements
  # The computed replacements for the Airtable rollups/formulas, confirmed
  # against the base schema export: committed/paid sum amount_excl_vat,
  # current_forecast is the latest forecast, remaining/variance derive from it.
  class BudgetTest < ActiveSupport::TestCase
    def build_budget(**attrs)
      Budget.create!(name: "Props", **attrs)
    end

    def add_expense(budget, status:, excl_vat:)
      Expense.create!(budget: budget, status: status, amount: excl_vat * 1.2r,
                      amount_excl_vat: excl_vat, description: "x")
    end

    test "committed_amount sums excl-VAT amounts of Approved, Submitted and Paid" do
      budget = build_budget
      add_expense(budget, status: Status::APPROVED, excl_vat: 10)
      add_expense(budget, status: Status::SUBMITTED, excl_vat: 20)
      add_expense(budget, status: Status::PAID, excl_vat: 5)
      add_expense(budget, status: Status::PENDING, excl_vat: 100)
      add_expense(budget, status: Status::REJECTED, excl_vat: 100)

      assert_equal BigDecimal("35"), budget.committed_amount
      assert_equal BigDecimal("5"), budget.total_paid
    end

    test "current_forecast is the latest forecast amount, nil when none" do
      budget = build_budget
      assert_nil budget.current_forecast
      assert_nil budget.remaining

      budget.forecasts.create!(amount: 100, date: Date.new(2026, 5, 1), reason: "initial")
      budget.forecasts.create!(amount: 150, date: Date.new(2026, 6, 1), reason: "revised")
      fresh = Budget.find(budget.id)
      assert_equal BigDecimal("150"), fresh.current_forecast
    end

    test "remaining and variance derive from the current forecast" do
      budget = build_budget(initial_budget: 120)
      budget.forecasts.create!(amount: 150, date: Date.new(2026, 6, 1), reason: "revised")
      add_expense(budget, status: Status::APPROVED, excl_vat: 40)

      fresh = Budget.find(budget.id)
      assert_equal BigDecimal("110"), fresh.remaining
      assert_equal BigDecimal("30"), fresh.variance
      assert_not fresh.over_budget?
    end

    test "over_budget? when committed exceeds the forecast; income budgets never" do
      budget = build_budget
      budget.forecasts.create!(amount: 10, date: Date.new(2026, 6, 1), reason: "small")
      add_expense(budget, status: Status::APPROVED, excl_vat: 40)
      assert Budget.find(budget.id).over_budget?

      income = build_budget(name: "Grant", budget_type: "Income")
      income.forecasts.create!(amount: 0, date: Date.new(2026, 6, 1), reason: "n/a")
      assert_not Budget.find(income.id).over_budget?
    end

    test "over_initial_budget? flags committed past the initial figure" do
      budget = build_budget(initial_budget: 30)
      budget.forecasts.create!(amount: 100, date: Date.new(2026, 6, 1), reason: "revised up")
      add_expense(budget, status: Status::APPROVED, excl_vat: 40)

      fresh = Budget.find(budget.id)
      assert_not fresh.over_budget?
      assert fresh.over_initial_budget?
    end

    test "owner_ids returns People record-id strings via the join table" do
      budget = build_budget
      alice = Person.create!(name: "Alice", email: "alice-owner@example.com")
      bob = Person.create!(name: "Bob", email: "bob-owner@example.com")
      budget.owners << alice << bob

      assert_equal [ alice.record_id, bob.record_id ].sort, budget.owner_ids.sort
      assert_kind_of String, budget.owner_ids.first
    end

    test "income? mirrors the PORO" do
      assert build_budget(name: "G", budget_type: "Income").income?
      assert_not build_budget(name: "E").income?
    end
  end
end
