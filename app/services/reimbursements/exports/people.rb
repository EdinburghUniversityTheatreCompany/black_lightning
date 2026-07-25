module Reimbursements
  module Exports
    ##
    # The payee registry, with a live modulus verdict per person.
    #
    # BANK DETAILS ARE MASKED to their last four digits ("****4958"). An export
    # is a file that leaves the portal — emailed, dropped in a shared drive,
    # kept in Downloads — where the finance permission that gates this page no
    # longer protects it. The last four digits are all finance needs to
    # eyeball-match a row against a BACS submission or a bank statement, and a
    # masked pair can't be used to move money. The BACS spreadsheet EUSA
    # actually pays from is the one place that still carries full numbers.
    class People < Base
      HEADERS = [ "Name", "Email", "Sort code", "Account number",
                  "Modulus check", "Verified" ].freeze
      SHEET_NAME = "People".freeze
      SLUG = "people".freeze

      # No bank details at all: the same word the on-screen badge uses, since it
      # blocks approval just as hard as a failed check.
      MISSING_LABEL = "Missing".freeze

      private

      def row(person)
        [
          person.name, person.email,
          mask(person.sort_code), mask(person.account_number),
          modulus_label(person), person.verified ? "Yes" : "No"
        ]
      end

      # Blank in, blank out (nil, so the cell is empty) — a person with no
      # details on file must not read as a redacted value that was never there.
      def mask(value)
        BankDetails.mask(value).presence
      end

      # The same vocabulary as the page's live badge: Valid / Invalid /
      # Outside spec / Missing.
      def modulus_label(person)
        return MISSING_LABEL unless person.bank_details?

        checker.check(person.sort_code, person.account_number).to_s.humanize
      end
    end
  end
end
