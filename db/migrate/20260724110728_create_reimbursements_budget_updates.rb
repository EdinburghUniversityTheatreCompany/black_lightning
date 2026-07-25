class CreateReimbursementsBudgetUpdates < ActiveRecord::Migration[8.1]
  def change
    create_table :reimbursements_budget_updates do |t|
      t.references :financial_year,
                   foreign_key: { to_table: :reimbursements_financial_years }
      t.date :effective_date, null: false
      t.text :note
      # `users` has a legacy INTEGER primary key, so the FK column must match
      # its type or the foreign-key migration aborts on a type mismatch.
      t.references :created_by, type: :integer,
                   foreign_key: { to_table: :users }
      t.timestamps
    end

    # Nullable link from a forecast to the batched update that logged it. All
    # existing standalone forecasts stay NULL, so "latest forecast wins" in
    # Budget#current_forecast is untouched — a batched forecast is still just a
    # BudgetForecast row.
    add_reference :reimbursements_budget_forecasts, :budget_update, index: true

    # The reimbursements forecast table is tiny (a handful of rows per budget),
    # so the brief write lock from adding this FK is negligible; assert it for
    # strong_migrations rather than splitting into a separate migration.
    safety_assured do
      add_foreign_key :reimbursements_budget_forecasts, :reimbursements_budget_updates,
                      column: :budget_update_id
    end
  end
end
