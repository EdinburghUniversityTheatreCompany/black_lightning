class RemoveNotificationRoleFromReimbursementsCostCentres < ActiveRecord::Migration[8.1]
  # The notification role is gone: a cost centre's reminders go to its own shared
  # finance mailbox (notification_email), which holds several addresses when it
  # needs to, so the role bought nothing the column doesn't.
  #
  # BACKFILL FIRST. notification_email becomes required, and dropping the role
  # from a row that has no address would both invalidate the row (every later
  # update! on it -- record_nightly_run! included -- would raise) and silently
  # stop that centre's reminders. So any centre without an address inherits the
  # emails of whoever is in its role today, semicolon-joined: exactly the people
  # being emailed before this migration ran.
  #
  # A centre whose role is empty (or unset) has nobody to inherit from and is
  # left blank -- there is no address to invent. NightlyBatchJob already warns
  # and refuses to record the run-day in that case, so it keeps alarming until
  # somebody fills it in, which is the same behaviour an empty role had.
  # safety_assured on both halves. The backfill is an UPDATE strong_migrations
  # cannot inspect inside #execute; it touches at most a handful of rows (one per
  # cost centre) on a table with two. The column drop is safe because nothing
  # reads notification_role_id any more -- the association, the validation, the
  # Settings field and the Status card all go in this same change, so there is no
  # window where running code selects a dropped column.
  def up
    safety_assured { backfill_notification_email_from_roles }

    safety_assured do
      remove_foreign_key :reimbursements_cost_centres, column: :notification_role_id
      remove_reference :reimbursements_cost_centres, :notification_role, type: :integer
    end
  end

  # Structure only: the addresses that were derived from the role stay in
  # notification_email, because there is no way to tell a backfilled address
  # from a typed one, and guessing which Role a list of emails came from would
  # be worse than leaving it.
  def down
    safety_assured do
      add_reference :reimbursements_cost_centres, :notification_role, type: :integer, index: true
      add_foreign_key :reimbursements_cost_centres, :roles, column: :notification_role_id
    end
  end

  private

  def backfill_notification_email_from_roles
    rows = select_all(<<~SQL.squish)
      SELECT cc.id AS id,
             GROUP_CONCAT(DISTINCT u.email ORDER BY u.email SEPARATOR '; ') AS emails
      FROM reimbursements_cost_centres cc
      JOIN users_roles ru ON ru.role_id = cc.notification_role_id
      JOIN users u ON u.id = ru.user_id
      WHERE (cc.notification_email IS NULL OR cc.notification_email = '')
        AND u.email IS NOT NULL AND u.email != ''
      GROUP BY cc.id
    SQL

    rows.each do |row|
      execute(<<~SQL.squish)
        UPDATE reimbursements_cost_centres
        SET notification_email = #{quote(row['emails'])}
        WHERE id = #{row['id'].to_i}
      SQL
      say("Backfilled cost centre #{row['id']} notification_email from its role", true)
    end
  end
end
