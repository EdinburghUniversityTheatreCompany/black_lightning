class CreateReimbursementsBudgets < ActiveRecord::Migration[8.1]
  # Budgets mirroring the Airtable Budgets table (Phase H cutover).
  #
  # The Airtable rollups/formulas (current_forecast, committed_amount,
  # total_paid, remaining, variance) are NOT stored — the AR model computes
  # them from expenses + forecasts (formulas confirmed from the base schema
  # export; see docs/reimbursements/mysql-migration-and-roadmap.md).
  #
  # cost_centre: an expense resolves its cost centre via its budget — this FK
  # is what makes per-cost-centre scoping (nightly, Build Batch, Reconcile)
  # possible. Nullable; the importer backfills the default centre.
  # financial_year: nullable now, backfilled by the importer; the year-selector
  # UI lands post-cutover.
  #
  # Budget owners are a join table (reimbursements_budget_owners), not a
  # single owner FK — ownership is many-to-many with People (not users).
  def change
    create_table :reimbursements_budgets do |t|
      t.string :name, null: false, default: ""
      t.string :nominal_code, null: false, default: ""
      t.boolean :active, null: false, default: true
      t.string :budget_type, null: false, default: "Expense"
      t.decimal :initial_budget, precision: 12, scale: 2
      t.text :notes
      t.references :cost_centre, type: :bigint, null: true,
                                 foreign_key: { to_table: :reimbursements_cost_centres }, index: true
      t.references :financial_year, type: :bigint, null: true,
                                    foreign_key: { to_table: :reimbursements_financial_years }, index: true
      t.string :airtable_record_id

      t.timestamps
    end

    add_index :reimbursements_budgets, :nominal_code
    add_index :reimbursements_budgets, :airtable_record_id, unique: true
  end
end
