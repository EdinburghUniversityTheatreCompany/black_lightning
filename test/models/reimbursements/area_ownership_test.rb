require "test_helper"

module Reimbursements
  class AreaOwnershipTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    setup do
      @alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      @bob   = create_reimbursements_person(name: "Bob", email: "bob@example.com")
    end

    test "a budget in an area inherits the area's owners" do
      area = create_reimbursements_area(name: "Cogito")
      area.sync_owner_ids!([ @alice.id ])
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      assert_equal [ @alice.record_id ], budget.owner_ids
    end

    test "a budget with no area keeps its own owners" do
      budget = create_reimbursements_budget(name: "Contingency")
      budget.sync_owner_ids!([ @bob.id ])

      assert_equal [ @bob.record_id ], budget.owner_ids
    end

    test "the area's owners WIN over rows left on the budget" do
      # The backfill keeps budget_owners rows so it can be reversed; they must
      # not also apply, or a claim would need two people's sign-off.
      area = create_reimbursements_area(name: "Cogito")
      area.sync_owner_ids!([ @alice.id ])
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)
      budget.sync_owner_ids!([ @bob.id ])

      assert_equal [ @alice.record_id ], budget.owner_ids
    end

    test "the owner gate reads the inherited owner" do
      area = create_reimbursements_area(name: "Cogito")
      area.sync_owner_ids!([ @alice.id ])
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)
      expense = create_reimbursements_expense(budget: budget)

      assert OwnerReview.gate_applies?(expense)
      assert OwnerReview.owned_by?(expense, @alice)
    end
  end
end
