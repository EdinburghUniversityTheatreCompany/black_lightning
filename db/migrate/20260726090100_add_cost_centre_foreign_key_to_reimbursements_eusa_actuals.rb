class AddCostCentreForeignKeyToReimbursementsEusaActuals < ActiveRecord::Migration[8.1]
  # The cost_centre_id FK, kept separate from the column add per the multi-step
  # convention. Same up/down shape as
  # AddOffsetOfForeignKeyToReimbursementsEusaActuals — strong_migrations'
  # recommended MySQL pattern for adding an FK without blocking writes on both
  # tables. Skipping existing-row validation is sound here because the previous
  # migration set every non-NULL value from a join against the very table this
  # FK points at.
  def up
    safety_assured do
      execute "SET SESSION foreign_key_checks = 0"
      add_foreign_key :reimbursements_eusa_actuals, :reimbursements_cost_centres,
                      column: :cost_centre_id
    ensure
      execute "SET SESSION foreign_key_checks = 1"
    end
  end

  def down
    remove_foreign_key :reimbursements_eusa_actuals, column: :cost_centre_id
  end
end
