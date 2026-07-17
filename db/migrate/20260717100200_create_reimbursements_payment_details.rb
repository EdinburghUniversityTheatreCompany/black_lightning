class CreateReimbursementsPaymentDetails < ActiveRecord::Migration[8.1]
  # Bank details as a first-class model, split out of Person (per Mick's
  # directive in the cutover design). One-to-one today (unique person_id);
  # if a payee ever needs multiple accounts this becomes has_many + a primary
  # flag, without touching Person.
  def change
    create_table :reimbursements_payment_details do |t|
      t.references :person, type: :bigint, null: false,
                            foreign_key: { to_table: :reimbursements_people }, index: { unique: true }
      t.string :sort_code, null: false, default: ""
      t.string :account_number, null: false, default: ""
      t.boolean :verified, null: false, default: false
      t.text :notes

      t.timestamps
    end
  end
end
