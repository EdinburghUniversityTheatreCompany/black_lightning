require "test_helper"

module Reimbursements
  class SpendSummaryTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    setup do
      @person = create_reimbursements_person(name: "Pat", email: "pat@example.com")
    end

    # Left is not Budget#remaining, which ignores the pipeline; both are wanted.
    test "left subtracts BOTH committed spend and claims still waiting" do
      budget = create_reimbursements_budget(name: "Props", initial_budget: 1_000)
      spend(budget, 200, Status::PAID)
      spend(budget, 300, Status::PENDING)

      summary = SpendSummary.for_budget(budget)

      assert_equal 1_000, summary.budget_amount
      assert_equal 200, summary.spent
      assert_equal 300, summary.waiting
      assert_equal 500, summary.left
      assert_equal 800, budget.remaining, "remaining ignores the pipeline"
    end

    test "left is negative and over_by positive when the budget is blown" do
      budget = create_reimbursements_budget(name: "Props", initial_budget: 100)
      spend(budget, 2_526.13, Status::PAID)

      summary = SpendSummary.for_budget(budget)

      assert summary.over?
      assert_equal(-2_426.13, summary.left)
      assert_equal 2_426.13, summary.over_by
    end

    # PlannedAmount: a £0 plan is unset, not a cap all spend is over.
    test "a line with no plan, or a plan of exactly zero, has no left rather than a zero" do
      [ nil, 0 ].each do |plan|
        budget = create_reimbursements_budget(name: "Props #{plan.inspect}", initial_budget: plan)
        spend(budget, 50, Status::PAID)

        summary = SpendSummary.for_budget(budget)

        assert summary.no_budget_set?, "plan #{plan.inspect}"
        assert_nil summary.left, "plan #{plan.inspect}"
        assert_not summary.over?, "plan #{plan.inspect}"
        assert_not summary.bar?, "plan #{plan.inspect}"
      end
    end

    test "an area with an agreed total compares against it" do
      area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
      line = create_reimbursements_budget(name: "Marketing", area: area, initial_budget: 400)
      spend(line, 100, Status::APPROVED)
      spend(line, 25, Status::PENDING)

      summary = SpendSummary.for_area(area.reload)

      assert_equal 1_000, summary.budget_amount
      assert_not summary.from_lines?
      assert_equal 100, summary.spent
      assert_equal 25, summary.waiting
      assert_equal 875, summary.left
      assert_equal 600, summary.unallocated
    end

    test "an area with no agreed total falls back to what its lines add up to" do
      area = create_reimbursements_area(name: "Improverts")
      create_reimbursements_budget(name: "Marketing", area: area, initial_budget: 1_100)
      create_reimbursements_budget(name: "Retreat", area: area, initial_budget: 1_500)
      create_reimbursements_budget(name: "Other", area: area, initial_budget: 100)

      summary = SpendSummary.for_area(area.reload)

      assert_equal 2_700, summary.budget_amount
      assert summary.from_lines?
      assert_nil summary.unallocated
    end

    test "an area with no total or a zero total, and unbudgeted lines, has no budget but still totals spend" do
      [ nil, 0 ].each do |total|
        area = create_reimbursements_area(name: "Tech #{total.inspect}", initial_budget: total)
        line = create_reimbursements_budget(name: "Tech #{total.inspect}", area: area)
        spend(line, 3_273.20, Status::PAID)

        summary = SpendSummary.for_area(area.reload)

        assert summary.no_budget_set?, "total #{total.inspect}"
        assert_nil summary.left, "total #{total.inspect}"
        assert_equal 3_273.20, summary.spent, "total #{total.inspect}"
      end
    end

    test "an area with no lines at all still reports its agreed total" do
      area = create_reimbursements_area(name: "Nativity", initial_budget: 120)

      summary = SpendSummary.for_area(area.reload)

      assert_equal 120, summary.budget_amount
      assert_equal 0, summary.spent
      assert_equal 120, summary.left
      assert_equal 120, summary.unallocated
    end

    # Expense and income are never totalled together.
    test "income lines are left out of budget, spent, waiting and left" do
      area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
      expense_line = create_reimbursements_budget(name: "Marketing", area: area,
                                                  initial_budget: 400)
      income_line = create_reimbursements_budget(name: "Ticket income", area: area,
                                                 budget_type: "Income", initial_budget: 800)
      spend(expense_line, 100, Status::APPROVED)
      spend(income_line, 60, Status::PENDING)

      summary = SpendSummary.for_area(area.reload)

      assert_equal 1_000, summary.budget_amount
      assert_equal 100, summary.spent
      assert_equal 0, summary.waiting
      assert_equal 900, summary.left
    end

    # Area#unallocated is reused, so the page and the area edit card cannot disagree.
    test "unallocated follows the area's own basis" do
      area = create_reimbursements_area(name: "Committee", initial_budget: 1_000,
                                        budget_basis: Area::BASIS_NET)
      create_reimbursements_budget(name: "Spend", area: area, initial_budget: 400)
      create_reimbursements_budget(name: "Income", area: area, budget_type: "Income",
                                   initial_budget: 800)

      area.reload
      assert_equal area.unallocated, SpendSummary.for_area(area).unallocated
      assert_equal 1_400, SpendSummary.for_area(area).unallocated
    end

    test "the bar scales to the overspend so it fills rather than overflows" do
      budget = create_reimbursements_budget(name: "Props", initial_budget: 100)
      spend(budget, 300, Status::PAID)

      summary = SpendSummary.for_budget(budget)

      assert summary.bar?
      assert_equal 300, summary.bar_scale
      assert_equal 100.0, summary.spent_percentage
      assert_equal 0.0, summary.waiting_percentage
    end

    test "the bar splits spent from waiting" do
      budget = create_reimbursements_budget(name: "Props", initial_budget: 1_000)
      spend(budget, 500, Status::PAID)
      spend(budget, 250, Status::PENDING)

      summary = SpendSummary.for_budget(budget)

      assert_equal 50.0, summary.spent_percentage
      assert_equal 25.0, summary.waiting_percentage
    end

    private

    def spend(budget, amount, status)
      create_reimbursements_expense(person: @person, budget: budget, status: status,
                                    amount: amount, amount_excl_vat: amount, receipt: false)
    end
  end
end
