module Reimbursements
  # Once-a-day IT-subcommittee alert for a Graph credential failure (GraphAuth::AuthError).
  # Every Graph job shares one Entra credential, so one shared dedup key sends a single email
  # however many jobs hit it in a cycle. The alert goes through ActionMailer, not Graph, since
  # Graph is what's broken.
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
