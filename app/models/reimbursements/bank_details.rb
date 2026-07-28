module Reimbursements
  ##
  # Shared UK bank-detail rules for the portal forms. Sort codes are stored in
  # the conventional dashed form ("80-22-60"); the modulus check strips the
  # dashes itself.
  module BankDetails
    SORT_CODE_HINT = "must be 6 digits, e.g. 80-22-60.".freeze
    ACCOUNT_NUMBER_HINT = "must be 8 digits.".freeze

    # A payee account name is a bank-account holder name, not free prose: BACS
    # itself carries 18 characters and Faster Payments 140, and the value ends up
    # in a spreadsheet cell EUSA pays from. 255 is the pre-encryption varchar
    # limit kept as the user-visible rule, so no name already on file is now
    # rejected, and it stays far inside the widened TEXT column once encryption
    # inflates it (255 characters -> ~394 bytes of ciphertext).
    PAYEE_NAME_MAX_LENGTH = 255
    PAYEE_NAME_HINT = "must be #{PAYEE_NAME_MAX_LENGTH} characters or fewer.".freeze

    # Sort codes and account numbers are format-validated to 6 and 8 digits on
    # every write path, so this is only a backstop for direct model writes. It has
    # to stay well under the ~123-character plaintext that fills a string(255)
    # column once encrypted.
    BANK_DIGITS_MAX_LENGTH = 32

    module_function

    def normalize_sort_code(value)
      value.to_s.gsub(/[-\s]/, "")
    end

    def format_sort_code(value)
      digits = normalize_sort_code(value)
      return value if digits.length != 6

      digits.scan(/\d{2}/).join("-")
    end

    def valid_sort_code?(value)
      normalize_sort_code(value).match?(/\A\d{6}\z/)
    end

    def normalize_account_number(value)
      value.to_s.gsub(/\s/, "")
    end

    def valid_account_number?(value)
      normalize_account_number(value).match?(/\A\d{8}\z/)
    end

    # A bank detail reduced to its last four digits ("66374958" -> "****4958").
    # For anywhere a value is RECORDED or EXPORTED rather than used to move
    # money: the People audit trail in the notes, and the CSV/workbook exports,
    # which are files that leave the portal. Only the BACS spreadsheet EUSA
    # actually pays from carries full numbers.
    #
    # Non-digits are stripped first, so a dashed sort code masks cleanly. A
    # value shorter than four digits (in practice unreachable — both fields are
    # format-validated before they are stored) masks whatever is present rather
    # than exposing it. Blank in, blank out, so an export cell stays empty
    # instead of reading as a redacted value that was never there.
    def mask(value)
      digits = value.to_s.gsub(/\D/, "")
      return "" if digits.empty?

      "****#{digits[-4..] || digits}"
    end

    # A payee-name/sort-code/account-number override trio must be all-or-
    # nothing: setting only one or two would splice a third party's partial
    # bank details onto the payee's own remaining fields — an internally-
    # inconsistent pair that still passes each field's own format check.
    def overrides_incomplete?(payee_name, sort_code, account_number)
      overrides = [ payee_name, sort_code, account_number ]
      overrides.any?(&:present?) && !overrides.all?(&:present?)
    end

    # No override at all, so the payee falls back to the submitter's own bank
    # details: correct on a Reimbursement, a misdirected payment on an Invoice.
    def overrides_missing?(payee_name, sort_code, account_number)
      [ payee_name, sort_code, account_number ].all?(&:blank?)
    end
  end
end
