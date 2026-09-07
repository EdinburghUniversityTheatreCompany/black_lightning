module Reimbursements
  ##
  # Who gets a cost centre's OPERATOR mail -- the nightly's stale-pending and
  # ready-to-batch reminders, and its failure alert. One definition, so the job
  # and any later caller cannot drift apart on it.
  #
  # It is the cost centre's own shared finance mailbox
  # (finance@bedlamfringe.co.uk, business@bedlamtheatre.co.uk), which is
  # monitored by whoever holds the job rather than by whichever accounts happen
  # to sit in a role. +notification_email+ takes several addresses, so it covers
  # what the retired notification_role was for.
  #
  # NB the budget-owner sign-off reminder does NOT come through here: it is
  # addressed to each owner's own Person#email (NightlyBatchJob).
  #
  # REIMBURSEMENTS_OPERATOR_EMAIL stays whole-portal and wins outright: it is the
  # "divert everything to one inbox" switch, so scoping it per centre would
  # defeat the only thing it exists for.
  module NotificationRecipients
    def self.for(cost_centre)
      override = ENV["REIMBURSEMENTS_OPERATOR_EMAIL"].presence
      return [ override ] if override

      cost_centre&.notification_emails || []
    end
  end
end
