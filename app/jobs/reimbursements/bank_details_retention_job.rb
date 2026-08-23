module Reimbursements
  ##
  # Nightly storage-limitation sweep: clears bank details for payees who have
  # not filed a claim in BankDetailsRetention::RETENTION_PERIOD.
  #
  # Deliberately silent when it clears nothing, which is most nights. It sends
  # no notification even when it does: a payee whose details have aged out is
  # asked for them again by the submission form the next time they claim, so
  # there is nothing for anyone to act on, and a "we deleted your bank details"
  # email would read as an incident rather than as housekeeping.
  class BankDetailsRetentionJob < ApplicationJob
    queue_as :default

    def perform
      cleared = BankDetailsRetention.erase_stale!
      Rails.logger.info("Reimbursements bank-details retention: cleared #{cleared} payee(s)") if cleared.positive?
      cleared
    end
  end
end
