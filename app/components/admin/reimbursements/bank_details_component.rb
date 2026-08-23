module Admin
  module Reimbursements
    ##
    # A payee's sort code and account number, masked until an operator asks to
    # see them.
    #
    # This is a disclosure control, not an access control: everyone who can
    # reach these screens is entitled to the numbers, and the full values are in
    # the markup behind the toggle. What it stops is the incidental exposure —
    # Build Batch printing every payee's account number the moment the page
    # loads, a screen shared in a meeting, a queue scrolled past in an open-plan
    # office. Reading one becomes a deliberate act.
    #
    # The mask is ::Reimbursements::BankDetails.mask, the same last-four form the
    # CSV exports and the notes audit trail use, so a row can be eyeball-matched
    # across all three without revealing anything. That it leaves four of a sort
    # code's six digits showing is not a problem worth solving: a sort code
    # names a bank branch and is published; the account number is the part that
    # needs covering.
    class BankDetailsComponent < ViewComponent::Base
      # Names the payee in the toggle's accessible name, so a screen reader on a
      # table of twenty claims hears which one each button belongs to.
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
