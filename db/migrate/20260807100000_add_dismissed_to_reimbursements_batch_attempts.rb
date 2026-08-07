class AddDismissedToReimbursementsBatchAttempts < ActiveRecord::Migration[8.1]
  # A failed build's banner had no way to be cleared: it stayed on History until
  # the seven-day window aged it out, long after the operator had fixed the
  # problem and rebuilt. A red banner nobody can clear becomes wallpaper, and
  # the next real failure hides among the stale ones.
  #
  # Dismissing flags rather than deletes, because the row is the audit trail of
  # a build attempt, and one carrying a batch_record_id is the only pointer to
  # a draft that may still exist in the mailbox.
  def change
    add_column :reimbursements_batch_attempts, :dismissed_at, :datetime
    add_column :reimbursements_batch_attempts, :dismissed_by_email, :string

    # needing_attention filters on this alongside status, and History reads it
    # on every page load.
    add_index :reimbursements_batch_attempts, %i[cost_centre_id dismissed_at],
              name: "idx_batch_attempts_on_cost_centre_and_dismissed"
  end
end
