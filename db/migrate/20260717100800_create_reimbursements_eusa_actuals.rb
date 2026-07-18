class CreateReimbursementsEusaActuals < ActiveRecord::Migration[8.1]
  # EUSA ledger rows imported during reconciliation (Phase H cutover). The
  # PORO's linked_expense_ids/linked_budget_ids arrays wrap these single FKs —
  # reconcile only ever links one of each.
  def change
    create_table :reimbursements_eusa_actuals do |t|
      t.string :nominal_code, null: false, default: ""
      t.string :cost_centre, null: false, default: ""
      t.string :ref
      t.date :date
      t.string :period
      t.text :narrative
      t.text :narrative_1
      t.decimal :debit, precision: 12, scale: 2
      t.decimal :credit, precision: 12, scale: 2
      t.decimal :net, precision: 12, scale: 2
      t.string :source_month, null: false, default: ""
      t.datetime :imported_at

      t.references :expense, type: :bigint, null: true,
                             foreign_key: { to_table: :reimbursements_expenses }, index: true
      t.references :budget, type: :bigint, null: true,
                            foreign_key: { to_table: :reimbursements_budgets }, index: true
      t.references :financial_year, type: :bigint, null: true,
                                    foreign_key: { to_table: :reimbursements_financial_years }, index: true

      t.string :airtable_record_id

      t.timestamps
    end

    # Reconcile dedups within a period; import joins on airtable_record_id.
    add_index :reimbursements_eusa_actuals, :nominal_code
    add_index :reimbursements_eusa_actuals, :period
    add_index :reimbursements_eusa_actuals, :source_month
    add_index :reimbursements_eusa_actuals, :airtable_record_id, unique: true
  end
end
