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
  end
end
