# One budget's share of a single EUSA credit row, so a Stripe payout covering
# five shows can land on five income lines instead of one.
#
# Both parent tables have bigint primary keys, so plain t.references is right
# here; the legacy integer-PK trap applies to `opportunities` and friends.
#
# The unique index is declared INSIDE create_table deliberately: a standalone
# add_index beside a foreign key makes create_table irreversible, and this
# table's rollback has to actually run.
class CreateReimbursementsActualAllocations < ActiveRecord::Migration[8.1]
  def change
    create_table :reimbursements_actual_allocations do |t|
      t.references :eusa_actual, null: false, type: :bigint,
                   foreign_key: { to_table: :reimbursements_eusa_actuals }
      t.references :budget, null: false, type: :bigint,
                   foreign_key: { to_table: :reimbursements_budgets }
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.timestamps
      t.index %i[eusa_actual_id budget_id], unique: true,
              name: "index_reimb_actual_allocations_on_actual_and_budget"
    end
  end
end
