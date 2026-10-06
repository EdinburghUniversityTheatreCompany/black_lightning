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
        cleared = stale(as_of: as_of).each { |details| erase!(details) }
        # Names, never digits.
        cleared.each do |details|
          Rails.logger.info("Reimbursements bank-details retention: cleared #{details.person&.name}")
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

      # The details' own timestamp counts too: re-verified details are current
      # even when the last claim is old, and unused ones still age out.
      def last_activity(details, person)
        [ details.updated_at, *person.expenses.map(&:updated_at) ].compact.max
      end
    end
  end
end
