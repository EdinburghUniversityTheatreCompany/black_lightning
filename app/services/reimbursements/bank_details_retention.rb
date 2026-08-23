module Reimbursements
  ##
  # Clears bank details the portal has no remaining reason to hold.
  #
  # A sort code and account number are collected for one purpose: to pay a
  # claim. Once a payee has not filed one for RETENTION_PERIOD there is no
  # purpose left, and an account number sitting on file is only a liability —
  # the storage-limitation half of what the encryption-at-rest work started.
  #
  # What is emphatically NOT touched: the Person, their expenses, or the
  # existing audit trail in +notes+. Those are the society's financial records,
  # kept because they have to be; it is the part that can move money that goes.
  # An erasure request is a different thing and takes the whole PaymentDetails
  # row with it (see User#erase_reimbursements_bank_details).
  class BankDetailsRetention
    RETENTION_PERIOD = 6.months

    # Statuses where money may still move into the account on file. Derived by
    # subtraction on purpose: a status added later counts as live until someone
    # decides otherwise, which is the safe direction — the failure mode of the
    # other default is clearing the details of a claim about to be paid.
    LIVE_STATUSES = (Status.all - [ Status::PAID, Status::REJECTED ]).freeze

    class << self
      # Clears every stale payee's details; returns how many were cleared.
      def erase_stale!(as_of: Time.current)
        stale(as_of: as_of).each { |details| erase!(details) }.size
      end

      def stale(as_of: Time.current)
        cutoff = as_of - RETENTION_PERIOD
        # "Has a sort code on file" cannot be a WHERE clause: the columns are
        # encrypted non-deterministically, so the ciphertext differs per row and
        # per write. It is read per record instead — the payee registry is a few
        # dozen rows, and this runs once a night.
        PaymentDetails.includes(person: :expenses).select { |details| stale?(details, cutoff) }
      end

      def stale?(details, cutoff)
        return false if details.sort_code.blank? && details.account_number.blank?

        person = details.person
        return false if person.nil?
        return false if person.expenses.any? { |expense| LIVE_STATUSES.include?(expense.status) }

        last_activity(details, person) < cutoff
      end

      def erase!(details)
        details.update!(
          sort_code: "", account_number: "", verified: false,
          notes: PaymentDetails.append_note(
            details.notes,
            "Bank details cleared: no claim activity for #{RETENTION_PERIOD.inspect} (retention)."
          )
        )
      end

      private

      # The details' own timestamp counts alongside the claims, so details
      # entered (or re-verified by finance) recently are current even when the
      # last claim is old — and details entered and never used still age out.
      def last_activity(details, person)
        [ details.updated_at, *person.expenses.map(&:updated_at) ].compact.max
      end
    end
  end
end
