require "test_helper"
require Rails.root.join("db/migrate/20260911100300_backfill_reimbursements_areas")

module Reimbursements
  class AreaRenameTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    test "leaves an area-less budget alone" do
      budget = create_reimbursements_budget(name: "Contingency")
      Reimbursements::AreaRename.strip!
      assert_equal "Contingency", budget.reload.name
    end

    # Matched through BudgetImport.match_key, so the casing the committee typed
    # does not decide whether a line keeps its prefix.
    test "strips a prefix that differs from its area only in case and spacing" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "cogito :  Marketing", area: area)

      Reimbursements::AreaRename.strip!
      assert_equal "Marketing", budget.reload.name

      Reimbursements::AreaRename.restore!
      assert_equal "cogito :  Marketing", budget.reload.name,
                   "restore! puts back what was recorded, not what the rule would rebuild"
    end

    # A rename after the strip is finance's own; a rollback must not take it back.
    test "restore! leaves a line finance has renamed since" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      Reimbursements::AreaRename.strip!
      budget.reload.update!(name: "Publicity")
      Reimbursements::AreaRename.restore!

      assert_equal "Publicity", budget.reload.name
    end

    # RENAMING THE AREA does not rename the line, so the record is still good and
    # restore! must still put the name back.
    test "restore! puts the name back after its area is renamed or re-cased" do
      %w[Cabaret cogito].each do |new_name|
        area = create_reimbursements_area(name: "Cogito")
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

        Reimbursements::AreaRename.strip!
        area.update!(name: new_name)
        Reimbursements::AreaRename.restore!

        assert_equal "Cogito: Marketing", budget.reload.name, "area renamed to #{new_name}"
      end
    end

    # A line moved to another area still restores: the backfill's verdict on the
    # area it landed in is the same either way.
    test "a line moved to another area restores without making that area reproducible" do
      budget = create_reimbursements_budget(name: "Cogito: Marketing")
      AreaBackfill.run!
      improverts = create_reimbursements_area(name: "Improverts")

      Reimbursements::AreaRename.strip!
      budget.reload.update!(area: improverts)
      Reimbursements::AreaRename.restore!

      assert_equal "Cogito: Marketing", budget.reload.name
      error = assert_raises(ActiveRecord::IrreversibleMigration) { BackfillReimbursementsAreas.new.down }
      assert_match(/Improverts/, error.message)
    end

    # A line with no area has nothing for the prefix to name.
    test "restore! leaves a line detached from its area alone" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      Reimbursements::AreaRename.strip!
      budget.reload.update!(area: nil)
      Reimbursements::AreaRename.restore!

      assert_equal "Marketing", budget.reload.name
    end

    # Phase 2b drops the column; skipping then would make a rollback that cannot
    # restore the names look like one that did.
    test "restore! refuses when the recording column is gone" do
      error = assert_raises(Reimbursements::AreaRename::MissingRecordError) do
        Reimbursements::AreaRename.restore!(scope: Area.all)
      end
      assert_match(/name_before_area_rename/, error.message)
    end

    # The row strip! refused to touch: restoring it by rule would make its area
    # reproducible and disarm the backfill's refusal, turning a guard into a
    # silent delete.
    test "restore! leaves a line it never stripped alone" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Rehearsal room hire", area: area)

      Reimbursements::AreaRename.strip!
      Reimbursements::AreaRename.restore!

      assert_equal "Rehearsal room hire", budget.reload.name,
                   "someone renamed this by hand; that is not this migration's to rewrite"
      assert_nil budget.name_before_area_rename
    end

    # Two lines in one area would land on one name: a merge nobody asked for.
    test "strip! refuses to collide two lines in one area" do
      area = create_reimbursements_area(name: "Cogito")
      bare = create_reimbursements_budget(name: "Marketing", area: area)
      prefixed = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      error = assert_raises(Reimbursements::AreaRename::CollisionError) do
        Reimbursements::AreaRename.strip!
      end
      assert_match(/two lines in one area/, error.message)

      assert_equal "Marketing", bare.reload.name
      assert_equal "Cogito: Marketing", prefixed.reload.name, "nothing was written"
    end

    # A collision already there is not this rename's doing; refusing over it would
    # block it on data it cannot fix.
    test "strip! tolerates a collision it did not create" do
      area = create_reimbursements_area(name: "Cogito")
      one = create_reimbursements_budget(name: "Marketing", area: area)
      two = create_reimbursements_budget(name: "marketing", area: area)
      moved = create_reimbursements_budget(name: "Cogito: Set", area: area)

      Reimbursements::AreaRename.strip!

      assert_equal "Set", moved.reload.name
      assert_equal "Marketing", one.reload.name
      assert_equal "marketing", two.reload.name
    end

    # A half-run migration is re-run whole, so neither direction may double-apply.
    test "both directions are idempotent" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      2.times { Reimbursements::AreaRename.strip! }
      assert_equal "Marketing", budget.reload.name

      2.times { Reimbursements::AreaRename.restore! }
      assert_equal "Cogito: Marketing", budget.reload.name
    end

    # update_columns, not update!: a bookkeeping rename must not fire
    # Budget#inherit_area_scoping.
    test "neither direction stamps the budget's year or cost centre" do
      centre = CostCentre.default
      year = FinancialYear.create!(label: "Fringe 2027")
      area = create_reimbursements_area(name: "Cogito", cost_centre: centre, financial_year: year)
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)
      # The line inherit_area_scoping would claim: unstamped, inside a stamped area.
      budget.update_columns(financial_year_id: nil, cost_centre_id: nil)

      Reimbursements::AreaRename.strip!
      Reimbursements::AreaRename.restore!

      assert_nil budget.reload.financial_year_id
      assert_nil budget.cost_centre_id
    end

    test "a scope narrows which budgets are rewritten" do
      area = create_reimbursements_area(name: "Cogito")
      mine = create_reimbursements_budget(name: "Cogito: Marketing", area: area)
      theirs = create_reimbursements_budget(name: "Cogito: Set", area: area)

      Reimbursements::AreaRename.strip!(scope: Budget.where(id: mine.id))

      assert_equal "Marketing", mine.reload.name
      assert_equal "Cogito: Set", theirs.reload.name
    end

    # --- The two migrations reverse together ---
    # The backfill's down refuses an area whose name no budget reproduces, which
    # stripping makes true by design: the rename's own down runs first and
    # rebuilds every name.

    # An area the backfill would not have created (finance or the importer made
    # it) must still make its down refuse after a round trip; restoring by rule
    # would fabricate the reproducibility and delete the area.
    test "a round trip leaves a hand-made area still unreproducible" do
      derived = create_reimbursements_budget(name: "Cogito: Marketing")
      AreaBackfill.run!
      hand_made = create_reimbursements_area(name: "Improverts")
      create_reimbursements_budget(name: "Retreat", area: hand_made)

      Reimbursements::AreaRename.strip!
      Reimbursements::AreaRename.restore!

      error = assert_raises(ActiveRecord::IrreversibleMigration) { BackfillReimbursementsAreas.new.down }
      assert_match(/nothing in the backfill would have created/, error.message)
      assert_match(/Improverts/, error.message)
      assert_equal "Cogito: Marketing", derived.reload.name
      assert_equal 2, Area.count, "refusing means refusing"
    end

    test "the rename's down hands the backfill a tree it can unwind" do
      budget = create_reimbursements_budget(name: "Cogito: Marketing")
      AreaBackfill.run!

      Reimbursements::AreaRename.strip!
      Reimbursements::AreaRename.restore!
      BackfillReimbursementsAreas.new.down

      assert_equal "Cogito: Marketing", budget.reload.name
      assert_nil budget.area_id
      assert_equal 0, Area.count
    end
  end
end
