class CreateReimbursementsBatches < ActiveRecord::Migration[8.1]
  # BACS batches (Phase H cutover). No eusa_draft_created boolean — a present
  # draft_message_id means the draft exists (roadmap Phase H step 6 drops the
  # redundant flag); the model derives the legacy predicate for old sent
  # batches from date_sent. The generated EUSA xlsx becomes an ActiveStorage
  # has_one_attached :bacs_request_file.
  def change
    create_table :reimbursements_batches do |t|
      t.string :name, null: false, default: ""
      t.date :date_sent
      t.text :sharepoint_backup_url
      # Graph message id of the EUSA draft, kept so reopen can verify/delete
      # the stale draft in Outlook and so an ambiguous create can be retried
      # idempotently (find_batch_by_draft_message_id).
      t.string :draft_message_id
      t.boolean :producer_notifications_sent, null: false, default: false
      t.text :notes
      t.string :airtable_record_id

      t.timestamps
    end

    add_index :reimbursements_batches, :draft_message_id
    add_index :reimbursements_batches, :airtable_record_id, unique: true
  end
end
