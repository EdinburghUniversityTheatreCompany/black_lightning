module Reimbursements
  ##
  # Who gets a cost centre's OPERATOR mail -- the nightly's stale-pending and
  # ready-to-batch reminders, and its failure alert. One definition, so the job
  # and any later caller cannot drift apart on it.
  #
  # This replaced a global list: every user in every role holding the
  # `manage`/`reimbursements_finance` grid permission. That permission is still
  # what gates the finance SCREENS -- a Fringe admin can still open a termtime
  # claim. It is only who gets TOLD that is now per centre.
  #
  # REIMBURSEMENTS_OPERATOR_EMAIL stays whole-portal and wins outright: it is the
  # "divert everything to one inbox" switch, so scoping it per centre would
  # defeat the only thing it exists for.
  module NotificationRecipients
    def self.for(cost_centre)
      override = ENV["REIMBURSEMENTS_OPERATOR_EMAIL"].presence
      return [ override ] if override

      role = cost_centre&.notification_role
      return [] if role.nil?

      role.users.map(&:email).compact_blank.uniq
    end
  end
end
