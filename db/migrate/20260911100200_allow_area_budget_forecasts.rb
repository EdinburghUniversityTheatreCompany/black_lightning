class AllowAreaBudgetForecasts < ActiveRecord::Migration[8.1]
  # An AREA forecast revises the show's agreed total; a BUDGET forecast revises
  # how much of it a category is allocated. One BudgetUpdate groups both, so a
  # committee meeting stays one update.
  #
  # reimbursements_budget_forecasts is a live, populated table, so this follows
  # the same strong_migrations-safe pattern as 20260911100000
  # (create_reimbursements_areas): add_reference WITHOUT foreign_key:, then
  # add_foreign_key wrapped in safety_assured with foreign_key_checks disabled
  # around it — the execute calls themselves are independently flagged by
  # strong_migrations, so they must be inside safety_assured too, not just the
  # add_foreign_key call.
  #
  # A CHECK constraint backs up the model's belongs_to_exactly_one_owner
  # validation (belt and braces, as BudgetGoneError backs the budget FK): a
  # write that bypasses AR validations — update_column, insert_all, a future
  # data migration — must not silently produce a forecast with both or
  # neither owner. strong_migrations flags add_check_constraint on MySQL
  # unconditionally (there's no NOT VALID-then-validate two-step like
  # Postgres gets), so it needs safety_assured too; that's fine here since
  # the table is small and every existing row already satisfies the
  # constraint (budget_id set, area_id NULL), so validation is instant.
  CHECK_NAME = "budget_forecasts_exactly_one_owner"

  def up
    add_reference :reimbursements_budget_forecasts, :area, type: :bigint, null: true, index: true

    safety_assured do
      begin
        execute "SET SESSION foreign_key_checks = 0"
        add_foreign_key :reimbursements_budget_forecasts, :reimbursements_areas, column: :area_id
      ensure
        execute "SET SESSION foreign_key_checks = 1"
      end
    end

    change_column_null :reimbursements_budget_forecasts, :budget_id, true

    safety_assured do
      add_check_constraint :reimbursements_budget_forecasts,
                            "(budget_id IS NULL) != (area_id IS NULL)",
                            name: CHECK_NAME
    end
  end

  def down
    # Area forecasts have no home once the column goes; refuse rather than
    # silently dropping revisions to an agreed total.
    if Reimbursements::BudgetForecast.where.not(area_id: nil).exists?
      raise ActiveRecord::IrreversibleMigration,
            "area forecasts exist — reassign or delete them before rolling back"
    end

    remove_check_constraint :reimbursements_budget_forecasts, name: CHECK_NAME
    change_column_null :reimbursements_budget_forecasts, :budget_id, false
    remove_foreign_key :reimbursements_budget_forecasts, :reimbursements_areas, column: :area_id
    remove_reference :reimbursements_budget_forecasts, :area
  end
end
