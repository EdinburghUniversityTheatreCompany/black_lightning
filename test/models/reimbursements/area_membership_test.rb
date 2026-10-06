require "test_helper"
require Rails.root.join("db/migrate/20260911100300_backfill_reimbursements_areas")

module Reimbursements
  # BackfillReimbursementsAreas#down used to lose the area of any line whose NAME
  # does not reproduce it, and re-migrating did not put it back. The migration is
  # plain Ruby, so #down and #up run directly against the test database.
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

    # seed_owners! seeds from the children's OWN owner rows, so an area whose only
    # owner-carrying line was unprefixed came back naming nobody, switching
    # sign-off off for every other line under it too.
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

    # An area that names nobody is a real state, and the record says so: without
    # it, Bob's row on the LINE (what seed_owners! reads) would switch a gate ON
    # that finance had turned off.
    test "an area that named nobody still names nobody after a round trip" do
      bob = create_reimbursements_person(name: "Bob", email: "bob@example.com")
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

    # The record decides, never the line's current area: the backfill re-homes by
    # NAME, so a hand-moved line would land its recorded owners on the show its
    # name reads as. Own owners are cleared so seed_owners! contributes nothing.
    test "the recorded area wins over the name the backfill would re-home by" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      bob = create_reimbursements_person(name: "Bob", email: "bob@example.com")
      moved = create_reimbursements_budget(name: "ZZProbe Show: Sound")
      # Each area keeps a line whose name reproduces it, or #down refuses before
      # reaching the restore.
      create_reimbursements_budget(name: "ZZProbe Show: Marketing")
      create_reimbursements_budget(name: "ZZOther Show: Marketing")
      AreaBackfill.run!
      probe = Area.find_by!(name: "ZZProbe Show")
      other = Area.find_by!(name: "ZZOther Show")
      probe.sync_owner_ids!([ alice.id ])
      other.sync_owner_ids!([ bob.id ])
      moved.update_columns(area_id: other.id)
      Budget.find_each { |budget| budget.sync_owner_ids!([]) }

      BackfillReimbursementsAreas.new.down
      BackfillReimbursementsAreas.new.up

      assert_equal "ZZOther Show", moved.reload.area&.name,
                   "the hand-move is what the record knows and the name does not"
      assert_equal [ bob.record_id ], moved.area.owner_ids,
                   "and its owners are that area's, not the ones the name would have given it"
      assert_equal [ alice.record_id ], Area.find_by!(name: "ZZProbe Show").owner_ids
    end

    # The backfill keys on the BUDGET's year and centre, the record on the AREA's,
    # so a cross-year line makes the backfill mint an area the restore then
    # empties: an ownerless phantom in that year's pickers, which #down would
    # refuse over as hand-editing.
    test "a cross-year line leaves no phantom area behind, and rolls back again" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      this_year = FinancialYear.create!(label: "Fringe 2026", active: true)
      next_year = FinancialYear.create!(label: "Fringe 2027")
      area = create_reimbursements_area(name: "ZZCogito", financial_year: next_year)
      area.sync_owner_ids!([ alice.id ])
      budget = create_reimbursements_budget(name: "ZZCogito: Marketing", area: area,
                                            financial_year: this_year)

      BackfillReimbursementsAreas.new.down
      BackfillReimbursementsAreas.new.up

      assert_equal 1, Area.where(name: "ZZCogito").count,
                   "the area the backfill minted for this year is left holding nothing"
      assert_equal next_year.id, budget.reload.area.financial_year_id
      assert_equal [ alice.record_id ], budget.area.owner_ids
      # And the guard must not then refuse over an area the migration made.
      assert_nothing_raised { BackfillReimbursementsAreas.new.down }
    end

    # An area a PERSON made between rollback and re-migrate is one the backfill
    # merely finds, and an empty one can be intended: deleting it would tidy away
    # somebody else's work.
    test "an area a person made in the meantime survives being emptied" do
      this_year = FinancialYear.create!(label: "Fringe 2026", active: true)
      next_year = FinancialYear.create!(label: "Fringe 2027")
      area = create_reimbursements_area(name: "ZZCogito", financial_year: next_year)
      budget = create_reimbursements_budget(name: "ZZCogito: Marketing", area: area,
                                            financial_year: this_year)

      BackfillReimbursementsAreas.new.down
      # By hand, under the name the stranded line reads as: the backfill finds
      # it rather than making it.
      by_hand = create_reimbursements_area(name: "ZZCogito", financial_year: this_year)
      BackfillReimbursementsAreas.new.up

      assert Area.exists?(by_hand.id), "the backfill only clears the areas IT created"
      assert_empty by_hand.reload.budgets, "and the line still goes back where the record says"
      assert_equal next_year.id, budget.reload.area.financial_year_id
    end

    # The other half: an area this run created and the restore did NOT empty is
    # left alone, or the cleanup would delete the ordinary backfill's own work.
    test "an area the backfill created and still holds lines survives the cleanup" do
      budget = create_reimbursements_budget(name: "ZZCogito: Marketing")

      BackfillReimbursementsAreas.new.down
      BackfillReimbursementsAreas.new.up

      assert_equal "ZZCogito", budget.reload.area&.name
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

    # A rollback that cannot record where the lines were must say so rather than
    # detach silently. The REAL condition: the column is dropped and the service
    # must ask the LIVE schema, not its memoized column list (a wrong-model scope
    # would pass over a service that had stopped asking). DDL auto-commits on
    # MySQL and workers share a server, so the column goes back in an ensure.
    test "record! refuses when the recording column is gone" do
      error = without_recording_column do
        assert_raises(AreaMembership::MissingRecordError) { AreaMembership.record! }
      end
      assert_match(/area_before_rollback/, error.message)
      # The table is the scope's: a hardcoded one would answer "present" for every
      # other model.
      assert_raises(AreaMembership::MissingRecordError) { AreaMembership.record!(scope: Area.all) }
    end

    test "restore! refuses when the recording column is gone" do
      without_recording_column do
        assert_raises(AreaMembership::MissingRecordError) { AreaMembership.restore! }
      end
    end

    private

    # CREATE NOTHING IN A TEST THAT CALLS THIS: MySQL auto-commits DDL, so the drop
    # ends the test's transaction and the next write raises "SAVEPOINT
    # active_record_1 does not exist".
    #
    # The column cache is warmed before the drop and reset only afterwards, so the
    # memoized list and the live schema disagree inside the block; resetting first
    # would let a guard reading the cache pass the test it should fail.
    def without_recording_column
      connection = Budget.connection
      Budget.column_names
      connection.remove_column(:reimbursements_budgets, AreaMembership::RECORDED_COLUMN,
                               if_exists: true)
      yield
    ensure
      # Re-added at the SCHEMA-LOADED position (db/schema.rb lists columns
      # alphabetically; a migrated database has it second from last), with
      # if_exists/if_not_exists so a run killed halfway neither leaves the column
      # dropped nor drifts its order in that worker's database.
      connection.add_column(:reimbursements_budgets, AreaMembership::RECORDED_COLUMN, :json,
                            if_not_exists: true, after: :airtable_record_id)
      Budget.reset_column_information
    end
  end
end
