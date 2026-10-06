module Reimbursements
  module Exports
    ##
    # The payee registry, with a live modulus verdict per person.
    #
    # Bank details are MASKED to their last four digits ("****4958"): the file
    # leaves the portal, beyond the finance permission, and four digits are
    # enough to match a BACS submission or statement. Only the BACS spreadsheet
    # EUSA pays from carries full numbers.
    #
    # No "Cost centre" column: a payee has none, the same person claims from
    # whichever pot their claim's budget belongs to.
    class People < Base
      HEADERS = [ "Name", "Email", "Sort code", "Account number",
                  "Modulus check", "Verified" ].freeze
      SHEET_NAME = "People".freeze
      SLUG = "people".freeze

      # The on-screen badge's word for no bank details, which blocks approval
      # as hard as a failed check.
      MISSING_LABEL = "Missing".freeze

      private

      def row(person)
        [
          person.name, person.email,
          mask(person.sort_code), mask(person.account_number),
          modulus_label(person), person.verified ? "Yes" : "No"
        ]
      end

      # .presence: nothing on file is an empty cell, not a redacted value.
      def mask(value)
        BankDetails.mask(value).presence
      end

      # The page badge's vocabulary: Valid / Invalid / Outside spec / Missing.
      def modulus_label(person)
        return MISSING_LABEL unless person.bank_details?

        checker.check(person.sort_code, person.account_number).to_s.humanize
      end
    end
  end
end
