module Reimbursements
  # Daily check that warns the IT subcommittee (and Honeybadger) from 30 days before the Entra
  # client secret expires. Sudden auth failures are alerted separately through GraphAuthAlert.
  # Explicitly ::ApplicationJob: a bare constant here silently resolves to
  # Reimbursements::ApplicationJob, which this job (no store) must not inherit.
  class CredentialsCheckJob < ::ApplicationJob
    queue_as :default

    WARNING_WINDOW = 30.days
    # Mirrors GraphAuthAlert's dedup: the daily schedule usually makes it moot, but Solid
    # Queue's catch-up after downtime can enqueue several runs for one day, and an operator can
    # perform_now, either of which would resend the identical warning.
    WARNING_CACHE_KEY = "reimbursements/secret-expiry-warning".freeze

    def perform
      expires_on = Settings.azure_secret_expires_on
      return if expires_on.nil? || expires_on > WARNING_WINDOW.from_now.to_date

      # Honeybadger fires every run (cheap telemetry); only the email is deduped. Keep it outside
      # the fetch block: a raise after deliver_now inside it would skip caching the dedup key and
      # a retry would resend the email.
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
