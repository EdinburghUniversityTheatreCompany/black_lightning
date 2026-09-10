require "test_helper"

module Reimbursements
  class AreaBackfillTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    test "splits Area: Category names, tolerating extra whitespace" do
      a = create_reimbursements_budget(name: "Cogito: Marketing")
      b = create_reimbursements_budget(name: "Cogito: Other")
      c = create_reimbursements_budget(name: "Improverts:  Retreat")  # two spaces

      AreaBackfill.run!

      assert_equal "Cogito", a.reload.area.name
      assert_equal a.area, b.reload.area
      assert_equal "Improverts", c.reload.area.name
    end

    test "leaves a budget with no colon alone" do
      budget = create_reimbursements_budget(name: "Contingency")
      AreaBackfill.run!
      assert_nil budget.reload.area
    end

    test "seeds the area's owners from the union of its budgets'" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      bob = create_reimbursements_person(name: "Bob", email: "bob@example.com")
      a = create_reimbursements_budget(name: "Cogito: Marketing")
      b = create_reimbursements_budget(name: "Cogito: Other")
      a.sync_owner_ids!([ alice.id ])
      b.sync_owner_ids!([ bob.id ])

      AreaBackfill.run!

      assert_equal [ alice.record_id, bob.record_id ].sort, a.reload.area.owner_ids.sort
    end

    test "keeps the budgets' own owner rows, so the backfill can be reversed" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      budget = create_reimbursements_budget(name: "Cogito: Marketing")
      budget.sync_owner_ids!([ alice.id ])

      AreaBackfill.run!

      assert_equal [ alice.record_id ], budget.reload.own_owners.map(&:record_id)
    end

    test "does not re-home a budget that already has an area" do
      area = create_reimbursements_area(name: "Somewhere else")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      AreaBackfill.run!

      assert_equal area, budget.reload.area
    end

    test "running twice creates no duplicate area and does not re-seed owners a human already changed" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      bob = create_reimbursements_person(name: "Bob", email: "bob@example.com")
      a = create_reimbursements_budget(name: "Cogito: Marketing")
      b = create_reimbursements_budget(name: "Cogito: Other")
      a.sync_owner_ids!([ alice.id ])

      AreaBackfill.run!
      first_area = a.reload.area
      assert_equal 1, Area.where(name: "Cogito").count

      # Between runs, finance corrects the seeded owners by hand.
      first_area.sync_owner_ids!([ bob.id ])

      AreaBackfill.run!

      assert_equal 1, Area.where(name: "Cogito").count
      assert_equal first_area, a.reload.area
      assert_equal first_area, b.reload.area
      assert_equal [ bob.record_id ], first_area.reload.owner_ids
    end

    # MySQL gives a migration no automatic DDL transaction, so run! must supply
    # its own. Proved with a REAL failure, not a mock: a budget name whose area
    # segment strips to blank makes Area's presence validation raise partway
    # through find_each, with no mocking library available to inject a failure
    # more surgically.
    test "a mid-run failure rolls back every change — no budget is left homed" do
      a = create_reimbursements_budget(name: "Cogito: Marketing")
      create_reimbursements_budget(name: " : Something") # area segment strips to "" -> Area validation raises

      assert_raises(ActiveRecord::RecordInvalid) { AreaBackfill.run! }

      assert_nil a.reload.area_id
      assert_equal 0, Area.count
    end

    test "run!(scope:) only seeds owners for areas the scope's budgets actually touched" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      other_cc = create_second_reimbursements_cost_centre

      # An area outside the scope below, already homing a budget with owners
      # but never seeded (as if an earlier, narrower run left it alone).
      # seed_owners! must not reach across scope to seed it.
      outside_budget = create_reimbursements_budget(name: "Venue: Hire", cost_centre: other_cc)
      outside_budget.sync_owner_ids!([ alice.id ])
      outside_area = create_reimbursements_area(name: "Venue", cost_centre: other_cc)
      outside_budget.update_column(:area_id, outside_area.id)

      in_scope_budget = create_reimbursements_budget(name: "Cogito: Marketing")

      AreaBackfill.run!(scope: Budget.where(cost_centre_id: nil))

      assert_equal [], outside_area.reload.owner_ids
      assert_equal "Cogito", in_scope_budget.reload.area.name
    end
  end
end
