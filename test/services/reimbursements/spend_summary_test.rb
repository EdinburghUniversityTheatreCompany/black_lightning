require "test_helper"

module Reimbursements
  class SpendSummaryTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    setup do
      @person = create_reimbursements_person(name: "Pat", email: "pat@example.com")
    end

    # --- Left, the figure this class exists for ------------------------------

    test "left subtracts BOTH committed spend and claims still waiting" do
      budget = create_reimbursements_budget(name: "Props", initial_budget: 1_000)
      spend(budget, 200, Status::PAID)
      spend(budget, 300, Status::PENDING)

      summary = SpendSummary.for_budget(budget)

      assert_equal 1_000, summary.budget_amount
      assert_equal 200, summary.spent
      assert_equal 300, summary.waiting
      assert_equal 500, summary.left
    end

    # The whole reason Left is a new figure rather than a change to the
    # existing one: remaining ignores the pipeline, and both readings are
    # wanted, by different people, on different screens.
    test "left is not Budget#remaining, which ignores the pipeline" do
      budget = create_reimbursements_budget(name: "Props", initial_budget: 1_000)
      spend(budget, 300, Status::PENDING)

      assert_equal 1_000, budget.remaining
      assert_equal 700, SpendSummary.for_budget(budget).left
    end

    test "left is negative and over_by positive when the budget is blown" do
      budget = create_reimbursements_budget(name: "Props", initial_budget: 100)
      spend(budget, 2_526.13, Status::PAID)

      summary = SpendSummary.for_budget(budget)

      assert summary.over?
      assert_equal(-2_426.13, summary.left)
      assert_equal 2_426.13, summary.over_by
    end

    test "a line nobody set a budget for has no left, rather than a zero" do
      budget = create_reimbursements_budget(name: "Props")
      spend(budget, 50, Status::PAID)

      summary = SpendSummary.for_budget(budget)

      assert summary.no_budget_set?
      assert_nil summary.left
      assert_not summary.over?
      assert_not summary.bar?
    end

    # PlannedAmount's rule, reached through the summary: production carries
    # many £0 plans with real spend, and reading the 0 as a cap paints them all
    # over budget for ever.
    test "a plan of exactly zero counts as unset" do
      budget = create_reimbursements_budget(name: "Props", initial_budget: 0)
      spend(budget, 50, Status::PAID)

      assert SpendSummary.for_budget(budget).no_budget_set?
    end

    # --- Areas ---------------------------------------------------------------

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

    test "an area with a zero total and unbudgeted lines has no budget at all" do
      area = create_reimbursements_area(name: "Last years business", initial_budget: 0)
      line = create_reimbursements_budget(name: "Last years business", area: area)
      spend(line, 3_273.20, Status::PAID)

      summary = SpendSummary.for_area(area.reload)

      assert summary.no_budget_set?
      assert_nil summary.left
      assert_equal 3_273.20, summary.spent
    end

    test "an area with no lines at all still reports its agreed total" do
      area = create_reimbursements_area(name: "Nativity", initial_budget: 120)

      summary = SpendSummary.for_area(area.reload)

      assert_equal 120, summary.budget_amount
      assert_equal 0, summary.spent
      assert_equal 120, summary.left
      assert_equal 120, summary.unallocated
    end

    # The standing rule: expense and income are never totalled together, so an
    # area's headline figures cover its expense lines only.
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

    # Reuses Area#unallocated rather than restating it, so the page and the
    # area edit card cannot disagree for one area.
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

    test "an area whose lines are all unbudgeted still totals their spend" do
      area = create_reimbursements_area(name: "Tech")
      line = create_reimbursements_budget(name: "Tech", area: area)
      spend(line, 2_526.13, Status::PAID)

      summary = SpendSummary.for_area(area.reload)

      assert summary.no_budget_set?
      assert_equal 2_526.13, summary.spent
    end

    # --- The bar -------------------------------------------------------------

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
