class CreateReimbursementsPeople < ActiveRecord::Migration[8.1]
  # Payee registry mirroring the Airtable People table (Phase H cutover). Bank
  # details are NOT columns here — they live in the separate
  # reimbursements_payment_details table (one-to-one), per the cutover design.
  #
  # email is nullable and unique: the importer writes NULL for a blank Airtable
  # email (MySQL unique indexes allow multiple NULLs), and the unique index
  # closes the duplicate-People race in PersonLink#ensure_person! for good.
  # airtable_record_id is the importer's idempotency key.
  def change
    create_table :reimbursements_people do |t|
      t.string :name, null: false, default: ""
      t.string :email
      t.string :airtable_record_id

      t.timestamps
    end

    add_index :reimbursements_people, :email, unique: true
    add_index :reimbursements_people, :airtable_record_id, unique: true
  end
end
