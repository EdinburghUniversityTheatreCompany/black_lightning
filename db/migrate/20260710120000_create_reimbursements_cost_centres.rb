class CreateReimbursementsCostCentres < ActiveRecord::Migration[8.1]
  def change
    create_table :reimbursements_cost_centres do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :eusa_code, null: false
      # Distinct receive (email-in) and send-from mailboxes per cost centre.
      t.string :receive_mailbox, null: false
      t.string :send_mailbox, null: false

      t.timestamps
    end
    add_index :reimbursements_cost_centres, :key, unique: true
  end
end
