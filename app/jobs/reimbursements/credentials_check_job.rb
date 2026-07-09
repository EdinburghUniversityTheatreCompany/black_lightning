module Reimbursements
  ##
  # Daily check that warns the IT subcommittee (and Honeybadger) from 30 days
  # before the Entra client secret expires, so mailbox processing never dies
  # silently. Sudden auth failures are alerted separately by MailboxPollJob.
  class CredentialsCheckJob < ApplicationJob
    queue_as :default

    WARNING_WINDOW = 30.days

    def perform
      expires_on = Settings.azure_secret_expires_on
      return if expires_on.nil? || expires_on > WARNING_WINDOW.from_now.to_date

      ReimbursementsMailer.secret_expiry_warning(expires_on).deliver_now
      Honeybadger.event("reimbursements.secret_expiry_warning",
                        expires_on: expires_on.iso8601,
                        days_left: (expires_on - Date.current).to_i)
    end
  end
end
