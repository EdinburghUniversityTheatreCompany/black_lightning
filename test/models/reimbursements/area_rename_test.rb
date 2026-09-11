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
