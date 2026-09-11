class StripAreaPrefixFromBudgetNames < ActiveRecord::Migration[8.1]
  def up
    Reimbursements::AreaRename.strip!
  end

  # Reconstructs "Area: Category" for every line in an area. This is what keeps
  # the CHAIN reversible: BackfillReimbursementsAreas#down refuses to unwind an
  # area whose name no longer reproduces from any of its budgets, and #up leaves
  # exactly that state behind — correctly, since afterwards the area's name is
  # the only place the grouping lives. Rolling back both (STEP=2) runs this
  # first, so the backfill's guard sees the names it wrote.
  def down
    Reimbursements::AreaRename.restore!
  end
end
