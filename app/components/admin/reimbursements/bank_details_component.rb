module Admin
  module Reimbursements
    ##
    # A payee's sort code and account number, masked until an operator asks.
    #
    # A DISCLOSURE control, not an access control: the full pair is in the markup
    # behind the toggle. It stops incidental exposure (a screen shared in a
    # meeting), not anyone entitled to the numbers. The mask is the same last-four
    # form as the CSV exports and the notes trail.
    class BankDetailsComponent < ViewComponent::Base
      # +payee+ names the toggle for screen readers.
      def initialize(sort_code:, account_number:, payee: nil)
        @sort_code = sort_code.to_s
        @account_number = account_number.to_s
        @payee = payee.presence
      end

      private

      def blank_details? = @sort_code.blank? && @account_number.blank?

      def masked = join(::Reimbursements::BankDetails.mask(@sort_code), ::Reimbursements::BankDetails.mask(@account_number))

      def revealed = join(@sort_code, @account_number)

      def join(sort_code, account_number)
        [ sort_code.presence || "-", account_number.presence || "-" ].join(" / ")
      end

      def toggle_label
        @payee ? "bank details for #{@payee}" : "bank details"
      end
    end
  end
end
