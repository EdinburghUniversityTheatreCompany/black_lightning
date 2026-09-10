class BackfillReimbursementsAreas < ActiveRecord::Migration[8.1]
  def up
    Reimbursements::AreaBackfill.run!
  end

  def down
    # Detach, then drop the areas this created. The budgets' own owner rows were
    # deliberately kept, so ownership returns to exactly where it was.
    Reimbursements::Budget.where.not(area_id: nil).update_all(area_id: nil)
    Reimbursements::AreaOwner.delete_all
    Reimbursements::Area.delete_all
  end
end
