class AddAreaBeforeRollbackToReimbursementsBudgets < ActiveRecord::Migration[8.1]
  # Scratch column for the area backfill's rollback record, now unused. Dropped by
  # DropAreaRollbackRecordsFromReimbursementsBudgets, a later migration.
  def up
    add_column :reimbursements_budgets, :area_before_rollback, :json, if_not_exists: true
  end

  def down
    safety_assured do
      remove_column :reimbursements_budgets, :area_before_rollback, if_exists: true
    end
  end
end
