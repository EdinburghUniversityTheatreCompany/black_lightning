module Reimbursements
  ##
  # Daily check that warns the IT subcommittee (and Honeybadger) from 30 days
  # before the Entra client secret expires, so mailbox processing never dies
  # silently. Sudden auth failures are alerted separately by MailboxPollJob.
  class CredentialsCheckJob < ApplicationJob
    queue_as :default

    WARNING_WINDOW = 30.days
    # Mirrors MailboxPollJob#alert_auth_failure's dedup pattern: the schedule
    # (config/recurring.yml, once daily) already makes this a non-issue in the
    # ordinary case, but Solid Queue's recurring-task catch-up can enqueue more
    # than one run for the same day after downtime, and an operator can
    # perform_now this job manually — either would otherwise resend the
    # identical warning the same day.
    WARNING_CACHE_KEY = "reimbursements/secret-expiry-warning".freeze

    def perform
      expires_on = Settings.azure_secret_expires_on
      return if expires_on.nil? || expires_on > WARNING_WINDOW.from_now.to_date

      # Honeybadger fires every invocation (cheap telemetry, matches
      # GraphAuthAlert's same pattern); only the actual email is deduped. If
      # this were inside the fetch block instead, Honeybadger raising after a
      # successful deliver_now would abort the block before the dedup key got
      # cached, and the retried job would resend the identical email.
      Honeybadger.event("reimbursements.secret_expiry_warning",
                        expires_on: expires_on.iso8601,
                        days_left: (expires_on - Date.current).to_i)
      Rails.cache.fetch(WARNING_CACHE_KEY, expires_in: 1.day) do
        ReimbursementsMailer.secret_expiry_warning(expires_on).deliver_now
        true
      end
    end
  end
end
