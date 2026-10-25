# One claim's part of a single EUSA debit that paid several claims at once (EUSA combined a
# payee's claims into one payment), so each claim is settled and its budget counts its share.
#
# A claim takes at most one share (unique expense_id): a second would count its spend twice.
# Both parent tables have bigint primary keys. The indexes are declared INSIDE create_table: a
# standalone add_index beside a foreign key makes create_table irreversible.
class CreateReimbursementsClaimShares < ActiveRecord::Migration[8.1]
  def change
    create_table :reimbursements_claim_shares do |t|
      t.references :eusa_actual, null: false, type: :bigint,
                   foreign_key: { to_table: :reimbursements_eusa_actuals }
      t.references :expense, null: false, type: :bigint, index: { unique: true },
                   foreign_key: { to_table: :reimbursements_expenses }
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.timestamps
    end
  end
end
