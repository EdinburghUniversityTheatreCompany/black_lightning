module Reimbursements
  ##
  # Nightly sweep clearing bank details of payees with no claim in
  # BankDetailsRetention::RETENTION_PERIOD.
  #
  # Silent by design, no notification email: the submission form asks for the
  # details again on the next claim, so there is nothing to act on, and an email
  # would read as an incident.
  class BankDetailsRetentionJob < ApplicationJob
    queue_as :default

    def perform
      cleared = BankDetailsRetention.erase_stale!
      Rails.logger.info("Reimbursements bank-details retention: cleared #{cleared} payee(s)") if cleared.positive?
      cleared
    end
  end
end
