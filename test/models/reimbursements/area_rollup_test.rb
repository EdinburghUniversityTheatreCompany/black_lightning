require "test_helper"

module Reimbursements
  # The presenter behind the budget overview's area card: one area and the
  # budgets filed under it that the SCREEN is scoped to, subtotalled per type.
  class AreaRollupTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    setup do
      @area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
    end

    def line(**attrs)
      create_reimbursements_budget(area: @area, **attrs)
    end

    def rollup(budgets = @area.budgets.to_a)
      AreaRollup.new(area: @area, budgets: budgets)
    end

    test "an area rollup never totals Expense and Income together" do
      area = create_reimbursements_area(name: "Hamlet", initial_budget: 1_000)
      create_reimbursements_budget(name: "Marketing", area: area, initial_budget: 400,
                                   budget_type: "Expense")
      create_reimbursements_budget(name: "Ticket income", area: area, initial_budget: 800,
                                   budget_type: "Income")

      rollup = Reimbursements::AreaRollup.new(area: area, budgets: area.budgets)

      assert_equal %w[Expense Income].sort, rollup.by_type.map(&:budget_type).sort
      assert_equal 400, rollup.by_type.find { |r| r.budget_type == "Expense" }.initial
      assert_equal 800, rollup.by_type.find { |r| r.budget_type == "Income" }.initial
      # 1,200 is neither total spend nor net, so no rollup reports it.
      assert_empty rollup.by_type.select { |r| r.initial == BigDecimal("1200") }
    end

    test "sums each metric across the area's lines, treating a nil figure as zero" do
      props = line(name: "Props", initial_budget: 100)
      props.forecasts.create!(amount: 120, date: Date.new(2026, 6, 1), reason: "plan")
      Expense.create!(budget: props, status: Status::APPROVED, amount: 48,
                      amount_excl_vat: 40, description: "x")
      Expense.create!(budget: props, status: Status::PENDING, amount: 18,
                      amount_excl_vat: 15, description: "x")
      # No initial figure and no forecast, so its projected amount is nil.
      set = line(name: "Set")
      Expense.create!(budget: set, status: Status::PAID, amount: 36,
                      amount_excl_vat: 30, description: "x")

      totals = rollup([ Budget.find(props.id), Budget.find(set.id) ])

      assert_equal BigDecimal("100"), totals.initial
      assert_equal BigDecimal("120"), totals.projected
      assert_equal BigDecimal("70"), totals.committed
      assert_equal BigDecimal("15"), totals.pipeline
      assert_equal BigDecimal("30"), totals.paid_portal
      # Per budget: props = max(120, 40, 0, 0) = 120; set = max(0, 30, 30, 0) = 30.
      assert_equal BigDecimal("150"), totals.expected
    end

    test "expected outturn is blank on an income subtotal" do
      line(name: "Ticket income", budget_type: "Income", initial_budget: 800)

      income = rollup.by_type.find { |r| r.budget_type == "Income" }

      assert_nil income.expected
    end

    test "rows list the area's lines by name, and by_type omits an absent type" do
      line(name: "Set")
      line(name: "props")

      totals = rollup

      assert_equal %w[props Set], totals.rows.map(&:name)
      assert_equal [ "Expense" ], totals.by_type.map(&:budget_type)
    end

    test "the agreed total and what is unallocated come off the area, not the lines" do
      line(name: "Props", initial_budget: 400)

      totals = rollup

      assert_equal BigDecimal("1000"), totals.agreed
      assert_equal BigDecimal("600"), totals.unallocated
    end

    test "an area nobody agreed a total for reports nil, never zero" do
      area = create_reimbursements_area(name: "Unbudgeted")
      create_reimbursements_budget(name: "Props", area: area, initial_budget: 400)

      totals = AreaRollup.new(area: area, budgets: area.budgets.to_a)

      assert_nil totals.agreed
      assert_nil totals.unallocated
    end

    test "an area holding both budget types reports no allocation figure at all" do
      marketing = line(name: "Marketing", initial_budget: 400)
      line(name: "Ticket income", budget_type: "Income", initial_budget: 800)

      totals = rollup

      assert_predicate totals, :mixed_budget_types?
      # Area#unallocated subtracts both with no type filter: 1000 - 400 - 800.
      # A -200 on screen is indistinguishable from real over-allocation.
      assert_equal BigDecimal("-200"), @area.unallocated
      assert_nil totals.unallocated
      # The agreed total is one figure the committee agreed, not a sum, so it
      # survives.
      assert_equal BigDecimal("1000"), totals.agreed
      # Withheld on the strength of every line the area holds, not the ones on
      # screen — the figure it guards is summed over all of them too.
      assert_nil rollup([ marketing ]).unallocated
    end

    test "an area holding lines outside the screen's scope says how many are shown" do
      shown = line(name: "Props")
      line(name: "Set")
      line(name: "Costume")

      totals = rollup([ shown ])

      assert_equal 1, totals.lines_shown
      assert_equal 3, totals.lines_total
      assert_equal 2, totals.lines_out_of_scope
    end

    test "an area whose lines are all on screen reports nothing out of scope" do
      line(name: "Props")

      totals = rollup

      assert_equal 0, totals.lines_out_of_scope
      assert_equal 1, totals.lines_shown
    end

    test "the unassigned group carries no area and claims no lines out of scope" do
      loose = create_reimbursements_budget(name: "Contingency", initial_budget: 50)

      totals = AreaRollup.new(area: nil, budgets: [ loose ])

      assert_nil totals.name
      assert_nil totals.agreed
      assert_nil totals.unallocated
      assert_not totals.mixed_budget_types?
      assert_equal 0, totals.lines_out_of_scope
      assert_equal BigDecimal("50"), totals.initial
    end
  end
end
