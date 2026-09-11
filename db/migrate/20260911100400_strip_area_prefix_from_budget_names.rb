class StripAreaPrefixFromBudgetNames < ActiveRecord::Migration[8.1]
  # name_before_area_rename holds what each stripped line used to be called, so
  # #down restores exactly the rows #up touched and no others. Inference cannot
  # stand in for it: once stripped, a line that carried its area's prefix and
  # one that never did are the same string, and re-prefixing both fabricates
  # reproducibility for areas the backfill never derived — which disarms
  # BackfillReimbursementsAreas#down's refusal and turns it into a silent delete
  # of areas and their owner rows.
  #
  # Dead weight once the rollback window closes. Phase 2b should drop it.
  def up
    add_column :reimbursements_budgets, :name_before_area_rename, :string, if_not_exists: true
    Reimbursements::AreaRename.strip!
  end

  def down
    Reimbursements::AreaRename.restore!
    safety_assured do
      remove_column :reimbursements_budgets, :name_before_area_rename, if_exists: true
    end
  end
end
