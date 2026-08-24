module Admin
  module Reimbursements
    ##
    # A payee's sort code and account number, masked until an operator asks.
    #
    # A DISCLOSURE control, not an access control: everyone reaching these
    # screens is entitled to the numbers, and the full pair is in the markup
    # behind the toggle. What it stops is incidental exposure — Build Batch
    # printing every payee's account number on load, a screen shared in a
    # meeting. Reading one becomes a deliberate act.
    #
    # The mask is ::Reimbursements::BankDetails.mask, the same last-four form
    # the CSV exports and the notes trail use, so a row can be eyeball-matched
    # across all three. It leaves four of a sort code's six digits showing,
    # which is fine: a sort code names a bank branch and is published.
    class BankDetailsComponent < ViewComponent::Base
      # +payee+ names the toggle, so a screen reader on a table of twenty claims
      # hears which one each button belongs to.
      def initialize(sort_code:, account_number:, payee: nil, separator: " / ")
        @sort_code = sort_code.to_s
        @account_number = account_number.to_s
        @payee = payee.presence
        @separator = separator
      end

      private

      attr_reader :separator

      def blank_details? = @sort_code.blank? && @account_number.blank?

      def masked = join(mask(@sort_code), mask(@account_number))

      def revealed = join(@sort_code, @account_number)

      def mask(value)
        ::Reimbursements::BankDetails.mask(value).presence || "-"
      end

      def join(sort_code, account_number)
        [ sort_code.presence || "-", account_number.presence || "-" ].join(separator)
      end

      def toggle_label
        @payee ? "bank details for #{@payee}" : "bank details"
      end
    end
  end
end
