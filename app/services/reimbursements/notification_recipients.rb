module Reimbursements
  # Who gets a cost centre's OPERATOR mail: the nightly's stale-pending and ready-to-batch
  # reminders and its failure alert. It is the centre's own shared finance mailbox, monitored by
  # whoever holds the job rather than by whichever accounts sit in a role; +notification_email+
  # takes several addresses. Budget-owner sign-off reminders do NOT come through here (each
  # owner's own Person#email, NightlyBatchJob).
  #
  # REIMBURSEMENTS_OPERATOR_EMAIL is whole-portal and wins outright: it is the "divert
  # everything to one inbox" switch, so scoping it per centre would defeat it.
  module NotificationRecipients
    def self.for(cost_centre)
      override = ENV["REIMBURSEMENTS_OPERATOR_EMAIL"].presence
      return [ override ] if override

      cost_centre&.notification_emails || []
    end
  end
end
