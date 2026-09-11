require "test_helper"
require Rails.root.join("db/migrate/20260911100300_backfill_reimbursements_areas")

module Reimbursements
  class AreaRenameTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    test "strips the area's name and the colon from its budgets" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      Reimbursements::AreaRename.strip!

      assert_equal "Marketing", budget.reload.name
    end

    test "tolerates the extra whitespace the backfill tolerated" do
      area = create_reimbursements_area(name: "Improverts")
      budget = create_reimbursements_budget(name: "Improverts:  Retreat", area: area)

      Reimbursements::AreaRename.strip!

      assert_equal "Retreat", budget.reload.name
    end

    test "leaves an area-less budget alone" do
      budget = create_reimbursements_budget(name: "Contingency")
      Reimbursements::AreaRename.strip!
      assert_equal "Contingency", budget.reload.name
    end

    test "leaves a name that does not start with its own area's name alone" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Rehearsal room hire", area: area)

      Reimbursements::AreaRename.strip!

      assert_equal "Rehearsal room hire", budget.reload.name,
                   "someone renamed this by hand; that is not this migration's to rewrite"
    end

    test "restore! puts the prefix back" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      Reimbursements::AreaRename.strip!
      Reimbursements::AreaRename.restore!

      assert_equal "Cogito: Marketing", budget.reload.name
    end

    # The prefix is matched the way every other name in this importer is
    # matched — through BudgetImport.match_key — so the casing the committee
    # typed doesn't decide whether a line keeps its prefix for ever.
    test "strips a prefix that differs from its area only in case and spacing" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "cogito :  Marketing", area: area)

      Reimbursements::AreaRename.strip!
      assert_equal "Marketing", budget.reload.name

      Reimbursements::AreaRename.restore!
      assert_equal "cogito :  Marketing", budget.reload.name,
                   "restore! puts back what was recorded, not what the rule would rebuild"
    end

    # A rename finance made after the strip is theirs, and a rollback must not
    # quietly take it back: nothing records that "Publicity" ever existed.
    test "restore! leaves a line finance has renamed since" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      Reimbursements::AreaRename.strip!
      budget.reload.update!(name: "Publicity")
      Reimbursements::AreaRename.restore!

      assert_equal "Publicity", budget.reload.name
    end

    # RENAMING THE AREA does not rename the line, so the record is still good
    # and restoring it disarms nothing. The old clause read the area's CURRENT
    # name and skipped, destroying the record one statement before the column is
    # dropped.
    test "restore! puts the name back after its area is renamed" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      Reimbursements::AreaRename.strip!
      area.update!(name: "Cabaret")
      Reimbursements::AreaRename.restore!

      assert_equal "Cogito: Marketing", budget.reload.name
    end

    test "restore! puts the name back after its area is re-cased" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      Reimbursements::AreaRename.strip!
      area.update!(name: "cogito")
      Reimbursements::AreaRename.restore!

      assert_equal "Cogito: Marketing", budget.reload.name
    end

    # A line MOVED to another area restores, where it used to skip: its prefix
    # names neither that area nor any other, so the backfill's verdict on the
    # area it landed in is identical either way.
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

    # Phase 2b drops the column once the rollback window closes. Skipping then
    # would turn a rollback that CANNOT restore the names into one that silently
    # doesn't.
    test "restore! refuses when the recording column is gone" do
      error = assert_raises(Reimbursements::AreaRename::MissingRecordError) do
        Reimbursements::AreaRename.restore!(scope: Area.all)
      end
      assert_match(/name_before_area_rename/, error.message)
    end

    # THE ROW strip! REFUSED TO TOUCH. Restoring by rule re-prefixed it, which
    # made its area reproducible from its budgets and disarmed the backfill's
    # refusal — a guard turned into a silent delete.
    test "restore! leaves a line it never stripped alone" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Rehearsal room hire", area: area)

      Reimbursements::AreaRename.strip!
      Reimbursements::AreaRename.restore!

      assert_equal "Rehearsal room hire", budget.reload.name
      assert_nil budget.name_before_area_rename
    end

    # Two lines in one area that would land on one name. A merge nobody asked
    # for, and afterwards one line to every reader and to the matcher.
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

    # A collision that was already there is not this migration's doing, and
    # refusing over it would block the rename on data it cannot fix.
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

    # Re-running either direction has to be safe: a migration that half-ran is
    # re-run whole, and "Marketing" must not become ": Marketing" or the area's
    # name twice over.
    test "both directions are idempotent" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

      2.times { Reimbursements::AreaRename.strip! }
      assert_equal "Marketing", budget.reload.name

      2.times { Reimbursements::AreaRename.restore! }
      assert_equal "Cogito: Marketing", budget.reload.name
    end

    # update_column, not update! — a bookkeeping rename must not be vetoed by an
    # unrelated validation, and must not fire Budget#inherit_area_scoping on rows
    # it is not there to stamp. An unstamped legacy line is exactly the row that
    # callback would silently claim.
    test "neither direction stamps the budget's year or cost centre" do
      centre = CostCentre.default ||
               create_reimbursements_cost_centre(key: "fringe", name: "Bedlam Fringe",
                                                 eusa_code: "F40")
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

    # --- The two migrations reverse together ---------------------------------
    # Phase 1's backfill refuses to unwind an area whose name does not reproduce from
    # any of its budgets, and stripping the prefix is exactly that state — which
    # is correct, because once stripped the area's name is the only place the
    # grouping lives. The chain still reverses because the rename's own down
    # runs first and reconstructs every name.

    test "stripping alone would leave the backfill unable to unwind" do
      create_reimbursements_budget(name: "Cogito: Marketing")
      AreaBackfill.run!

      Reimbursements::AreaRename.strip!

      error = assert_raises(ActiveRecord::IrreversibleMigration) { BackfillReimbursementsAreas.new.down }
      assert_match(/nothing in the backfill would have created/, error.message)
    end

    # THE TEST THAT MATTERS. An area nothing in the backfill would have created
    # — finance made it, or the importer did — must still make the backfill's
    # down refuse after a round trip. Restoring by rule re-prefixed its bare
    # lines, fabricated the reproducibility and deleted the area.
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
