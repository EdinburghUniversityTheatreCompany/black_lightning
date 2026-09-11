class AddAreaBeforeRollbackToReimbursementsBudgets < ActiveRecord::Migration[8.1]
  # AreaMembership's scratch space: the area a budget was in, written by
  # BackfillReimbursementsAreas#down and read by its #up.
  #
  # The version deliberately sits BELOW that migration's. A rollback reverses in
  # descending version order, so this column outlives the down that writes it
  # and is dropped one step later; added at the end of the chain instead, it
  # would be dropped FIRST and the down would have nowhere to record.
  #
  # A database that applied the backfill BEFORE this branch has this migration
  # pending, so Rails runs it out of order on the next `db:migrate` — which is
  # what has to happen before that backfill can be rolled back at all (see its
  # own header).
  def up
    add_column :reimbursements_budgets, :area_before_rollback, :json, if_not_exists: true
  end

  def down
    safety_assured do
      remove_column :reimbursements_budgets, :area_before_rollback, if_exists: true
    end
  end
end
