require "test_helper"

module Reimbursements
  class AreaFiguresTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    setup do
      @area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
      @marketing = create_reimbursements_budget(name: "Cogito: Marketing", area: @area,
                                                initial_budget: 400)
      @other = create_reimbursements_budget(name: "Cogito: Other", area: @area)  # no allocation
    end

    test "allocated skips lines with no agreed figure" do
      assert_equal 400, @area.allocated
      assert_equal 600, @area.unallocated
    end

    test "committed sums its budgets' committed spend" do
      person = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      create_reimbursements_expense(person: person, budget: @marketing,
                                    amount: 150, amount_excl_vat: 150,
                                    status: Status::APPROVED)

      assert_equal 150, @area.committed_amount
      assert_equal 850, @area.remaining
    end

    test "an area with no agreed total has no remaining, rather than a wrong one" do
      area = create_reimbursements_area(name: "Improverts")
      assert_nil area.remaining
    end

    test "an area with no budgets at all has zero committed and allocated" do
      area = create_reimbursements_area(name: "Empty", initial_budget: 1_000)
      assert_equal 0, area.committed_amount
      assert_equal 0, area.allocated
      assert_equal 1_000, area.unallocated
    end

    test "an area whose budgets have no figure reports zero allocated and the whole total unallocated" do
      area = create_reimbursements_area(name: "Unallocated", initial_budget: 500)
      create_reimbursements_budget(name: "Line A", area: area)
      create_reimbursements_budget(name: "Line B", area: area)

      assert_equal 0, area.allocated
      assert_equal 500, area.unallocated
      assert_equal 0, area.committed_amount
    end

    test "an area with budgets but no agreed total has nil remaining and unallocated" do
      # Realistic backfill state: children exist but no total was agreed
      area = create_reimbursements_area(name: "Realistic")
      create_reimbursements_budget(name: "Line A", area: area)
      create_reimbursements_budget(name: "Line B", area: area)

      assert_nil area.remaining
      assert_nil area.unallocated
      assert_equal 0, area.allocated
    end

    test "an expenses-basis area ignores income when computing what is left" do
      area = create_reimbursements_area(name: "Cogito show", initial_budget: 1_000,
                                        budget_basis: "expenses")
      create_reimbursements_budget(name: "Show marketing", area: area, initial_budget: 400,
                                   budget_type: "Expense")
      create_reimbursements_budget(name: "Show ticket income", area: area, initial_budget: 800,
                                   budget_type: "Income")

      assert_equal 400, area.allocated, "a show's income does not buy it more room"
      assert_equal 600, area.unallocated
    end

    test "a net-basis area lets income raise the allowance" do
      area = create_reimbursements_area(name: "Committee", initial_budget: 1_000,
                                        budget_basis: "net")
      create_reimbursements_budget(name: "Committee socials", area: area, initial_budget: 400,
                                   budget_type: "Expense")
      create_reimbursements_budget(name: "Committee raffle", area: area, initial_budget: 800,
                                   budget_type: "Income")

      assert_equal(-400, area.allocated, "money raised offsets money spent")
      assert_equal 1_400, area.unallocated
    end

    test "an income line on a net-basis area with no agreed total still reports nil" do
      # The backfilled state, on the basis that nets: a 0 here would read as
      # fully overspent just as it would on a spend cap.
      area = create_reimbursements_area(name: "Unbudgeted committee", budget_basis: "net")
      create_reimbursements_budget(name: "Committee raffle 2", area: area, initial_budget: 800,
                                   budget_type: "Income")

      assert_nil area.unallocated
      assert_equal(-800, area.allocated)
    end
  end
end
