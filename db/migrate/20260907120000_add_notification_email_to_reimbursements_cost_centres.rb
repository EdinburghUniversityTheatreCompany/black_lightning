class AddNotificationEmailToReimbursementsCostCentres < ActiveRecord::Migration[8.1]
  # A cost centre's operator reminders go to its own shared finance mailbox
  # (finance@bedlamfringe.co.uk, business@bedlamtheatre.co.uk) rather than to
  # named humans. Semicolon-separated so a centre can name several addresses,
  # which is what the notification_role used to be for.
  #
  # Nullable with no backfill on purpose: the role stays as the fallback, so an
  # unset centre keeps emailing exactly who it emails today (see
  # Reimbursements::NotificationRecipients).
  def change
    add_column :reimbursements_cost_centres, :notification_email, :string
  end
end
