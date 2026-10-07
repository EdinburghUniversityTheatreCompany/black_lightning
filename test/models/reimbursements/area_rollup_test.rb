require "test_helper"

module Reimbursements
  # The budget overview's area card: one area and the budgets the screen is
  # scoped to, subtotalled per type.
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

    # A #by_type child is one TYPE's slice, so it must not answer the area's
    # figures (a lines_total its rows do not add up to, a whole-show total beside
    # half of it). A nil degrades safely where a wrong integer reads as a fact.
    test "a per-type subtotal answers no area figure of its own" do
      line(name: "Marketing", initial_budget: 400)
      line(name: "Ticket income", budget_type: "Income", initial_budget: 800)

      subtotal = rollup.by_type.first

      assert_nil subtotal.name
      assert_nil subtotal.agreed
      assert_nil subtotal.unallocated
      assert_nil subtotal.total_label
      assert_equal 1, subtotal.lines_total
      assert_equal 0, subtotal.lines_out_of_scope
    end

    test "the basis never reaches the per-type subtotals" do
      line(name: "Marketing", initial_budget: 400)
      line(name: "Ticket income", budget_type: "Income", initial_budget: 800)

      # The basis governs the area's agreed-total arithmetic only: "what did it
      # spend" and "how much room is left" differ, and only the second nets.
      figures = ->(totals) { totals.by_type.map { |r| [ r.budget_type, r.initial, r.projected, r.committed ] } }
      before = figures.call(rollup)
      @area.update!(budget_basis: "net")
      fresh = Area.find(@area.id)

      assert_equal %w[Expense Income], before.map(&:first).sort
      assert_equal before, figures.call(AreaRollup.new(area: fresh, budgets: fresh.budgets.to_a))
    end

    test "rows list the area's lines by name" do
      line(name: "Set")
      line(name: "props")

      assert_equal %w[props Set], rollup.rows.map(&:name)
    end

    test "an area nobody agreed a total for reports nil, never zero" do
      area = create_reimbursements_area(name: "Unbudgeted")
      create_reimbursements_budget(name: "Props", area: area, initial_budget: 400)

      totals = AreaRollup.new(area: area, budgets: area.budgets.to_a)

      assert_nil totals.agreed
      assert_nil totals.unallocated
    end

    test "an area holding both budget types allocates on its declared basis" do
      marketing = line(name: "Marketing", initial_budget: 400)
      line(name: "Ticket income", budget_type: "Income", initial_budget: 800)

      assert_equal "Agreed total (expenses)", rollup.total_label
      assert_equal BigDecimal("1000"), rollup.agreed
      # A spend cap: the £800 raised buys the show no more room.
      assert_equal BigDecimal("600"), rollup.unallocated

      # A fresh read: the figures are memoized per instance.
      @area.update!(budget_basis: "net")
      netted = AreaRollup.new(area: Area.find(@area.id), budgets: [ marketing ])

      # Summed over every line the area holds, not the ones on screen.
      assert_equal BigDecimal("1400"), netted.unallocated
      assert_equal "Agreed total (net)", netted.total_label
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

    test "the unassigned group carries no area and claims no lines out of scope" do
      loose = create_reimbursements_budget(name: "Contingency", initial_budget: 50)

      totals = AreaRollup.new(area: nil, budgets: [ loose ])

      assert_nil totals.name
      assert_nil totals.agreed
      assert_nil totals.unallocated
      assert_nil totals.total_label
      assert_equal 0, totals.lines_out_of_scope
      assert_equal BigDecimal("50"), totals.initial
    end
  end
end
