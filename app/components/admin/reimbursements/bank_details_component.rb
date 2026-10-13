module Admin
  module Reimbursements
    ##
    # A payee's sort code and account number, or an international claim's IBAN,
    # masked until an operator asks.
    #
    # A DISCLOSURE control, not an access control: the full value is in the markup
    # behind the toggle. It stops incidental exposure (a screen shared in a
    # meeting), not anyone entitled to the numbers. The mask is the same last-four
    # form as the CSV exports and the notes trail.
    class BankDetailsComponent < ViewComponent::Base
      # +iban+ replaces the UK pair. +payee+ names the toggle for screen readers.
      def initialize(sort_code: nil, account_number: nil, iban: nil, payee: nil)
        @parts = [ sort_code.to_s, account_number.to_s ]
        @parts = [ ::Reimbursements::BankDetails.format_iban(iban.to_s) ] unless iban.nil?
        @payee = payee.presence
      end

      private

      def blank_details? = @parts.all?(&:blank?)

      def masked = join(@parts.map { |part| ::Reimbursements::BankDetails.mask(part) })

      def revealed = join(@parts)

      def join(parts)
        parts.map { |part| part.presence || "-" }.join(" / ")
      end

      def toggle_label
        @payee ? "bank details for #{@payee}" : "bank details"
      end
    end
  end
end
