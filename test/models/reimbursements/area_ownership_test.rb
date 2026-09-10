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

    # The worst way to get ownership wrong, pinned: attaching a budget that has
    # its OWN owner to an area with none reports no owners at all, so the gate
    # stops applying — every claim on the line skips owner endorsement, the
    # nightly job never names it, and Review's Awaiting-owner tab never shows
    # it. Asserted through OwnerReview rather than the model, because the gate
    # is what the outcome actually is. Both forms now warn about it on screen.
    test "a budget in an area with NO owners has no owner gate at all" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area,
                                           owners: [ @alice ])
      expense = create_reimbursements_expense(budget: budget)

      assert_empty budget.owner_ids, "the area owns, and it names nobody"
      assert_not OwnerReview.gate_applies?(expense)
      assert OwnerReview.gate_satisfied?(expense)
      assert_not OwnerReview.owned_by?(expense, @alice),
                 "the row kept on the budget does not own it while it has an area"
    end
  end
end
