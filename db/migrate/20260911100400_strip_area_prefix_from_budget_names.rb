class StripAreaPrefixFromBudgetNames < ActiveRecord::Migration[8.1]
  # name_before_area_rename is AreaRename's scratch space — see there for why a
  # recorded string rather than a rule. Nothing else reads or writes it, so it
  # is added and dropped here: a column that outlived the rename would hold
  # stale names nobody would think to clear. Dead weight once the rollback
  # window closes; Phase 2b should drop it.
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
