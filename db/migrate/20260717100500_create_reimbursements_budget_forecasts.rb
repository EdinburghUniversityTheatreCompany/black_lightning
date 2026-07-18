class CreateReimbursementsBudgetForecasts < ActiveRecord::Migration[8.1]
  # Versioned projected-expenditure updates for a budget (the Airtable Budget
  # Forecasts table). The latest row (date desc) is the budget's
  # current_forecast — computed by the model, not stored. The Airtable "Name"
  # formula label is likewise computed, not a column.
  def change
    create_table :reimbursements_budget_forecasts do |t|
      t.references :budget, type: :bigint, null: false,
                            foreign_key: { to_table: :reimbursements_budgets }, index: true
      t.decimal :amount, precision: 12, scale: 2
      t.date :date
      t.text :reason
      t.string :airtable_record_id

      t.timestamps
    end

    add_index :reimbursements_budget_forecasts, :airtable_record_id, unique: true
  end
end
