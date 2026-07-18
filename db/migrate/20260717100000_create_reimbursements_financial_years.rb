class CreateReimbursementsFinancialYears < ActiveRecord::Migration[8.1]
  # A financial year ("Fringe 2026") is orthogonal to cost centre: each year has
  # its own budgets, expenses and actuals. Shipped in the Phase H cutover set so
  # the schema is right once — the year-selector UI lands post-cutover (see
  # docs/reimbursements/mysql-migration-and-roadmap.md, "Multi-financial-year").
  # Exactly-one-active is a model-level rule; the index serves the active lookup.
  def change
    create_table :reimbursements_financial_years do |t|
      t.string :label, null: false
      t.date :starts_on
      t.date :ends_on
      t.boolean :active, null: false, default: false

      t.timestamps
    end

    add_index :reimbursements_financial_years, :label, unique: true
    add_index :reimbursements_financial_years, :active
  end
end
