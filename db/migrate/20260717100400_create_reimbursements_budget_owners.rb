class CreateReimbursementsBudgetOwners < ActiveRecord::Migration[8.1]
  # Budget <-> People ownership, many-to-many (the Airtable Budgets "Owner"
  # link field). Owners are People (payees), not user accounts — a budget
  # owner may never have logged in. Phase E's approval flow reads this.
  def change
    create_table :reimbursements_budget_owners do |t|
      t.references :budget, type: :bigint, null: false,
                            foreign_key: { to_table: :reimbursements_budgets }, index: true
      t.references :person, type: :bigint, null: false,
                            foreign_key: { to_table: :reimbursements_people }, index: true

      t.timestamps
    end

    add_index :reimbursements_budget_owners, [ :budget_id, :person_id ], unique: true
  end
end
