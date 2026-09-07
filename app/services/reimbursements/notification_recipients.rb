module Reimbursements
  ##
  # Who gets a cost centre's OPERATOR mail -- the nightly's stale-pending,
  # awaiting-sign-off and ready-to-batch reminders, and its failure alert. One
  # definition, so the job and any later caller cannot drift apart on it.
  #
  # A cost centre's own shared finance mailbox (finance@bedlamfringe.co.uk,
  # business@bedlamtheatre.co.uk) is the intended destination, so
  # +notification_email+ wins whenever it is set. The +notification_role+ behind
  # it is the fallback for a centre that has not been given an address yet --
  # which is every centre configured before that column existed, so removing the
  # fallback would silently stop their reminders on deploy.
  #
  # REIMBURSEMENTS_OPERATOR_EMAIL stays whole-portal and wins outright: it is the
  # "divert everything to one inbox" switch, so scoping it per centre would
  # defeat the only thing it exists for.
  module NotificationRecipients
    def self.for(cost_centre)
      override = ENV["REIMBURSEMENTS_OPERATOR_EMAIL"].presence
      return [ override ] if override
      return [] if cost_centre.nil?

      addresses = cost_centre.notification_emails
      return addresses if addresses.any?

      role = cost_centre.notification_role
      return [] if role.nil?

      role.users.map(&:email).compact_blank.uniq
    end
  end
end
