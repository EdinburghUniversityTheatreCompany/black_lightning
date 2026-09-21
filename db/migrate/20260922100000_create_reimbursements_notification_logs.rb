class CreateReimbursementsNotificationLogs < ActiveRecord::Migration[8.1]
  # What the portal has emailed, one row per RECIPIENT.
  #
  # Integration Status could say whether Graph was reachable and when each cost
  # centre's nightly last completed, and nothing at all about what was sent to
  # whom — so "did this person get their reminder?" had no answer short of
  # asking them. A reminder that silently went to a dead address looked
  # identical to one that arrived.
  #
  # One row per recipient rather than per message, because that is the question
  # being asked: a pending reminder addressed to three finance addresses is
  # three separate facts about three people.
  #
  # Nullable cost centre: a message can be sent for an unplaced claim, and
  # losing the log row would be worse than recording it without a pot.
  def change
    create_table :reimbursements_notification_logs do |t|
      t.references :cost_centre, foreign_key: { to_table: :reimbursements_cost_centres },
                   type: :bigint, index: false
      t.string :kind, null: false
      t.string :recipient, null: false
      t.string :subject
      t.datetime :sent_at, null: false

      t.timestamps

      # The two reads the Status page makes: the most recent sends, and
      # everything sent to one address.
      t.index %i[sent_at id], name: "index_reimbursements_notification_logs_on_sent_at"
      t.index %i[recipient sent_at], name: "index_reimbursements_notification_logs_on_recipient"
      t.index %i[cost_centre_id sent_at], name: "index_reimbursements_notification_logs_on_centre"
    end
  end
end
