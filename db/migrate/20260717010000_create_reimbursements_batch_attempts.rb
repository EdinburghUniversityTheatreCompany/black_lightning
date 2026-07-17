class CreateReimbursementsBatchAttempts < ActiveRecord::Migration[8.1]
  def change
    # Build Batch runs as a background job whose only failure signal used to be
    # an email — History had no in-app record of a build that was still
    # running, failed before creating the Airtable Batch record, or found
    # nothing to build. Airtable's schema isn't ours to change, so the attempt
    # log lives in MySQL (and survives the planned cutover).
    create_table :reimbursements_batch_attempts do |t|
      t.references :cost_centre, null: false,
                                 foreign_key: { to_table: :reimbursements_cost_centres }
      t.string :status, null: false, default: "building"
      t.date :bacs_date
      t.string :triggered_by_email
      t.text :error_messages
      t.string :batch_record_id
      t.timestamps
    end

    add_index :reimbursements_batch_attempts, %i[cost_centre_id status]
  end
end
