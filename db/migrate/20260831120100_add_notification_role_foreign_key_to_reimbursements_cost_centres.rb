class AddNotificationRoleForeignKeyToReimbursementsCostCentres < ActiveRecord::Migration[8.1]
  # The notification_role_id FK, kept separate from the column add per the
  # multi-step convention — same up/down shape as
  # AddCostCentreForeignKeyToReimbursementsEusaActuals, which is
  # strong_migrations' recommended MySQL pattern for adding an FK without
  # blocking writes on both tables. Skipping existing-row validation is sound
  # here because the previous migration set every value from a row it had just
  # located in the very table this FK points at.
  #
  # to_table: :roles because the column is notification_role_id, which Rails
  # would otherwise resolve to a non-existent notification_roles table.
  def up
    safety_assured do
      execute "SET SESSION foreign_key_checks = 0"
      add_foreign_key :reimbursements_cost_centres, :roles, column: :notification_role_id
    ensure
      execute "SET SESSION foreign_key_checks = 1"
    end
  end

  def down
    remove_foreign_key :reimbursements_cost_centres, column: :notification_role_id
  end
end
