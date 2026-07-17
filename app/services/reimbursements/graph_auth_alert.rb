module Reimbursements
  ##
  # Shared once-daily IT-subcommittee alert for a Microsoft Graph app-only
  # credential failure (GraphAuth::AuthError). Every reimbursements job that
  # talks to Graph (MailboxPollJob, NightlyBatchJob, BuildBatchJob) shares the
  # same Entra client-credential, so a broken/expired secret affects all of
  # them identically — one shared dedup key means a credential failure hit by
  # more than one job in the same cycle sends a single email, not one per job.
  # The alert itself goes through ordinary ActionMailer (not Graph), since
  # Graph is exactly what's broken.
  module GraphAuthAlert
    CACHE_KEY = "reimbursements/auth-failure-alerted".freeze

    def self.notify(error, source:)
      Honeybadger.notify(error, context: { source: source })
      Rails.cache.fetch(CACHE_KEY, expires_in: 1.day) do
        ReimbursementsMailer.auth_failure(error.message).deliver_now
        true
      end
    end
  end
end
