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
  end
end
