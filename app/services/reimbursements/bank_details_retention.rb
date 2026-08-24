module Reimbursements
  ##
  # Clears bank details the portal has no remaining reason to hold: they are
  # collected to pay a claim, and after RETENTION_PERIOD without one an account
  # number on file is only a liability.
  #
  # NOT touched: the Person, their expenses, or the existing +notes+ trail —
  # financial records the society has to keep. An erasure request is a different
  # thing and takes the whole row (see User#erase_reimbursements_bank_details).
  class BankDetailsRetention
    RETENTION_PERIOD = 6.months

    # Stated as the TERMINAL set rather than the live one, so anything
    # unrecognised — a legacy row, a status added later, a value written past
    # the inclusion validation by update_column — counts as live and blocks the
    # clearing. That asymmetry decides every judgement call here: reading a
    # claim as finished when it isn't wipes details about to be paid with no
    # undo (encrypted, no plaintext behind them); the other way round merely
    # keeps them a while longer.
    TERMINAL_STATUSES = [ Status::PAID, Status::REJECTED ].freeze

    class << self
      # Clears every stale payee's details; returns how many were cleared.
      def erase_stale!(as_of: Time.current)
        cleared = stale(as_of: as_of).each { |details| erase!(details) }
        # Named in the log: the per-row note is only findable by someone who
        # already suspects a payee was cleared. Names, never digits.
        cleared.each do |details|
          Rails.logger.info("Reimbursements bank-details retention: cleared #{details.person&.name}")
        end
        cleared.size
      end

      def stale(as_of: Time.current)
        cutoff = as_of - RETENTION_PERIOD
        # "Has a sort code on file" cannot be a WHERE clause: the columns are
        # encrypted non-deterministically. Read per record instead — the
        # registry is a few dozen rows and this runs once a night.
        PaymentDetails.includes(person: :expenses).select { |details| stale?(details, cutoff) }
      end

      def stale?(details, cutoff)
        return false if details.sort_code.blank? && details.account_number.blank?

        person = details.person
        return false if person.nil?
        return false if person.expenses.any? { |expense| !TERMINAL_STATUSES.include?(expense.status) }

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

      # The details' own timestamp counts alongside the claims: details
      # re-verified by finance are current even when the last claim is old, and
      # details entered and never used still age out.
      def last_activity(details, person)
        [ details.updated_at, *person.expenses.map(&:updated_at) ].compact.max
      end
    end
  end
end
