module Reimbursements
  ##
  # Clears bank details held past RETENTION_PERIOD without a claim. Leaves the
  # Person, their expenses and the +notes+ trail, which are financial records. An
  # erasure request takes the whole row instead (User#erase_reimbursements_bank_details).
  class BankDetailsRetention
    RETENTION_PERIOD = 6.months

    # The TERMINAL set, not the live one: an unrecognised status (legacy row, a
    # later addition) counts as live and blocks clearing. Reading a live claim as
    # finished wipes details about to be paid with no undo; the other way round
    # only keeps them a while longer.
    TERMINAL_STATUSES = [ Status::PAID, Status::REJECTED ].freeze

    class << self
      # Clears every stale payee's details; returns how many were cleared.
      def erase_stale!(as_of: Time.current)
        cleared = stale(as_of: as_of)
        cleared.each do |details|
          erase!(details)
          # Names, never digits.
          Rails.logger.info("Reimbursements bank-details retention: cleared #{details.person.name}")
        end
        cleared.size
      end

      def stale(as_of: Time.current)
        cutoff = as_of - RETENTION_PERIOD
        # "Has a sort code" cannot be a WHERE clause: non-deterministic encryption.
        # The registry is a few dozen rows, read nightly.
        PaymentDetails.includes(person: :expenses).select { |details| stale?(details, cutoff) }
      end

      def stale?(details, cutoff)
        return false if details.sort_code.blank? && details.account_number.blank?
        return false if details.person.expenses.any? { |expense| !TERMINAL_STATUSES.include?(expense.status) }

        last_activity(details) < cutoff
      end

      # The details' own timestamp counts too: re-verified details are current
      # even when the last claim is old, and unused ones still age out.
      def last_activity(details)
        [ details.updated_at, *details.person.expenses.map(&:updated_at) ].max
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
    end
  end
end
