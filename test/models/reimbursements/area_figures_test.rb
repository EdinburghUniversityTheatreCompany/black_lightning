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

    test "an area with no budgets at all has zero committed and allocated" do
      area = create_reimbursements_area(name: "Empty", initial_budget: 1_000)
      assert_equal 0, area.committed_amount
      assert_equal 0, area.allocated
      assert_equal 1_000, area.unallocated
    end

    test "an area with budgets but no agreed total has nil remaining and unallocated" do
      # Realistic backfill state: children exist but no total was agreed. The
      # income line on a net basis makes the allocation non-zero, and the nil
      # plan still wins.
      area = create_reimbursements_area(name: "Realistic", budget_basis: "net")
      create_reimbursements_budget(name: "Line A", area: area)
      create_reimbursements_budget(name: "Line B", area: area)
      create_reimbursements_budget(name: "Raffle", area: area, initial_budget: 800,
                                   budget_type: "Income")

      assert_nil area.remaining
      assert_nil area.unallocated
      assert_equal(-800, area.allocated)
    end

    test "an expenses-basis area ignores income when computing what is left" do
      create_reimbursements_budget(name: "Cogito: Tickets", area: @area, initial_budget: 800,
                                   budget_type: "Income")

      assert_equal 400, @area.allocated, "a show's income does not buy it more room"
      assert_equal 600, @area.unallocated
    end

    test "a net-basis area lets income raise the allowance" do
      create_reimbursements_budget(name: "Cogito: Tickets", area: @area, initial_budget: 800,
                                   budget_type: "Income")
      @area.update!(budget_basis: "net")

      assert_equal(-400, @area.allocated, "money raised offsets money spent")
      assert_equal 1_400, @area.unallocated
    end

    # --- A £0 agreed total is unset, not a cap of nothing (see PlannedAmount) ---

    test "an area whose agreed total is zero, with nothing allocated, reads as unset" do
      area = create_reimbursements_area(name: "Termtime odds", initial_budget: 0)
      budget = create_reimbursements_budget(name: "Sundries", area: area)
      create_reimbursements_expense(budget: budget, status: ::Reimbursements::Status::APPROVED,
                                    amount: 200, amount_excl_vat: 200)

      area.reload
      assert_predicate area, :no_budget_set?
      assert_nil area.remaining, "a figure nobody filled in is not a cap that was blown"
      assert_nil area.unallocated
    end

    # The lines contradict the total, which is worth showing.
    test "a zero total WITH lines allocated under it is still a real statement" do
      area = create_reimbursements_area(name: "Contradicted", initial_budget: 0)
      create_reimbursements_budget(name: "Props budget", area: area, initial_budget: 400)

      area.reload
      assert_not area.no_budget_set?
      assert_equal(-400, area.unallocated)
    end
  end
end
