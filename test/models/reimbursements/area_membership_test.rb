require "test_helper"
require Rails.root.join("db/migrate/20260911100300_backfill_reimbursements_areas")

module Reimbursements
  # The rollback gap Phase 1 shipped and two Phase 2a reviewers reproduced: a
  # budget in an area whose NAME does not reproduce it came back from
  # BackfillReimbursementsAreas#down with its name intact and its area gone, and
  # re-migrating did not put it back. The migration is plain Ruby (no DDL), so
  # #down and #up run directly against the schema-loaded test database.
  class AreaMembershipTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # The whole point: a line the backfill cannot re-home from its name.
    test "a line the backfill would not re-home survives down and up" do
      prefixed = create_reimbursements_budget(name: "Cogito: Marketing")
      AreaBackfill.run!
      area = prefixed.reload.area
      hand_moved = create_reimbursements_budget(name: "Rehearsal room hire", area: area)

      BackfillReimbursementsAreas.new.down
      assert_nil hand_moved.reload.area_id, "down still detaches; it is up that has to put it back"

      BackfillReimbursementsAreas.new.up

      assert_equal "Cogito", hand_moved.reload.area&.name
      assert_equal hand_moved.area_id, prefixed.reload.area_id, "both lines belong to ONE area"
      assert_nil hand_moved.read_attribute(AreaMembership::RECORDED_COLUMN),
                 "the record is spent once it has been restored"
    end

    # The area's owner gate rode on the same loss: seed_owners! seeds an area
    # from its children's OWN owner rows, so an area whose only owner-carrying
    # line was the unprefixed one came back naming nobody — and an area naming
    # nobody switches sign-off off for every OTHER line under it too.
    test "the restored line brings the area's owner gate back with it" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      prefixed = create_reimbursements_budget(name: "Cogito: Marketing")
      AreaBackfill.run!
      area = prefixed.reload.area
      area.sync_owner_ids!([ alice.id ])
      create_reimbursements_budget(name: "Rehearsal room hire", area: area)

      BackfillReimbursementsAreas.new.down
      BackfillReimbursementsAreas.new.up

      assert_equal [ alice.record_id ], prefixed.reload.owner_ids,
                   "the prefixed line reads its owners through the area, which must name Alice again"
    end

    # An area that deliberately names nobody is a real state, and the record is
    # what says so: seeding it from a restored line's own owner rows would
    # switch a gate ON that finance had turned off.
    test "an area that named nobody still names nobody after a round trip" do
      bob = create_reimbursements_person(name: "Bob", email: "bob@example.com")
      # Bob's row on the LINE is what AreaBackfill#seed_owners! reads, so
      # without the recorded list the area comes back named by him — a gate
      # switched ON that finance had turned off.
      prefixed = create_reimbursements_budget(name: "Cogito: Marketing", owners: [ bob ])
      AreaBackfill.run!
      area = prefixed.reload.area
      area.sync_owner_ids!([])

      BackfillReimbursementsAreas.new.down
      BackfillReimbursementsAreas.new.up

      assert_empty prefixed.reload.area.owner_ids
    end

    # A line the backfill DOES re-home is re-homed by the backfill, and the
    # recorded area must not be created a second time beside the one it made.
    test "a prefixed line is re-homed once, not into a second area of the same name" do
      prefixed = create_reimbursements_budget(name: "Cogito: Marketing")
      AreaBackfill.run!

      BackfillReimbursementsAreas.new.down
      BackfillReimbursementsAreas.new.up

      assert_equal 1, Area.count
      assert_equal "Cogito", prefixed.reload.area&.name
    end

    # The record is the area's identity, not its id: down deletes the rows, so
    # an id would dangle. An area nothing reproduces is rebuilt from the record.
    test "restore! rebuilds an area no line's name reproduces" do
      year = FinancialYear.create!(label: "Fringe 2027", active: true)
      centre = CostCentre.default
      area = create_reimbursements_area(name: "Improverts", financial_year: year, cost_centre: centre)
      budget = create_reimbursements_budget(name: "Rehearsal room hire", area: area)

      AreaMembership.record!
      budget.update_columns(area_id: nil)
      AreaOwner.delete_all
      Area.delete_all

      AreaMembership.restore!

      restored = budget.reload.area
      assert_equal "Improverts", restored&.name
      assert_equal year.id, restored.financial_year_id
      assert_equal centre.id, restored.cost_centre_id
    end

    # A line with no area has nothing to record, and a restore must not invent
    # one for it.
    test "record! ignores a line in no area" do
      budget = create_reimbursements_budget(name: "ZZContingency")

      AreaMembership.record!
      AreaMembership.restore!

      assert_nil budget.reload.area_id
      assert_equal 0, Area.count
    end

    # Recording where the lines were is the whole reversibility claim, so a
    # rollback that cannot write it must say so rather than detach silently.
    test "record! refuses when the recording column is gone" do
      error = assert_raises(AreaMembership::MissingRecordError) do
        AreaMembership.record!(scope: Area.all)
      end
      assert_match(/area_before_rollback/, error.message)
    end

    test "restore! refuses when the recording column is gone" do
      assert_raises(AreaMembership::MissingRecordError) do
        AreaMembership.restore!(scope: Area.all)
      end
    end
  end
end
