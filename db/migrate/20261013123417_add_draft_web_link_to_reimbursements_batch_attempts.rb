class AddDraftWebLinkToReimbursementsBatchAttempts < ActiveRecord::Migration[8.1]
  # Whether a failed build made its EUSA draft decides whether building it again
  # drafts its claims twice, and History could not tell. TEXT, as on batches: a
  # Graph webLink can run past 255 characters. No backfill: an older attempt's
  # draft is unknown, and History says so.
  def change
    add_column :reimbursements_batch_attempts, :draft_web_link, :text
  end
end
