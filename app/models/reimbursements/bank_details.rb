module Reimbursements
  ##
  # Shared UK and international bank-detail rules. Sort codes are stored dashed
  # ("80-22-60"); the modulus check strips the dashes itself.
  module BankDetails
    SORT_CODE_HINT = "must be 6 digits, e.g. 80-22-60.".freeze
    ACCOUNT_NUMBER_HINT = "must be 8 digits.".freeze

    # 255 is the pre-encryption varchar limit, kept so no name already on file is
    # rejected; it stays inside the widened TEXT column once encrypted (~394 bytes).
    PAYEE_NAME_MAX_LENGTH = 255
    PAYEE_NAME_HINT = "must be #{PAYEE_NAME_MAX_LENGTH} characters or fewer.".freeze

    # Backstop for direct model writes (forms validate 6 and 8 digits). Must stay
    # well under the ~123-character plaintext a string(255) column holds once encrypted.
    BANK_DIGITS_MAX_LENGTH = 32

    # An IBAN is at most 34 characters (Malta, Saint Lucia) and a BIC 11. Backstops
    # for direct writes, inside the ~123-character encrypted limit.
    IBAN_MAX_LENGTH = 34
    BIC_MAX_LENGTH = 11
    IBAN_HINT = "must be a valid IBAN, e.g. DE89 3704 0044 0532 0130 00.".freeze
    BIC_HINT = "must be 8 or 11 characters, e.g. DEUTDEFF or DEUTDEFF500.".freeze

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

    # Last four digits ("66374958" -> "****4958"), for anything RECORDED or
    # EXPORTED rather than paid from: the notes audit trail and the CSV/workbook
    # exports. Only the BACS spreadsheet carries full numbers.
    # Non-digits are stripped first. Blank in, blank out, so an export cell stays
    # empty rather than reading as a redacted value that was never there.
    def mask(value)
      digits = value.to_s.gsub(/\D/, "")
      return "" if digits.empty?

      "****#{digits[-4..] || digits}"
    end

    # International (IBAN / BIC). Only SPACES are stripped: a hyphen or dot means
    # the value came from somewhere unexpected and should be looked at, not cleaned.

    def normalize_iban(value)
      value.to_s.gsub(/\s/, "").upcase
    end

    # Two letters (country), two check digits, then 11-30 alphanumerics.
    IBAN_PATTERN = /\A[A-Z]{2}\d{2}[A-Z0-9]{11,30}\z/

    # ISO 13616 mod-97 check. A shape check alone would accept 99% of typos
    # (a transposed or dropped character), and a wrong IBAN is money sent
    # somewhere unrecoverable.
    def valid_iban?(value)
      iban = normalize_iban(value)
      return false unless iban.match?(IBAN_PATTERN)

      # Move the country code and check digits to the end; letters read as A = 10 .. Z = 35.
      rearranged = iban[4..] + iban[0, 4]
      digits = rearranged.each_char.map { |char| char.match?(/[A-Z]/) ? (char.ord - 55).to_s : char }.join
      digits.to_i % 97 == 1
    end

    # Grouped in fours. An invalid value is returned untouched so a half-typed
    # IBAN on a re-rendered form reads as typed.
    def format_iban(value)
      return value unless valid_iban?(value)

      normalize_iban(value).scan(/.{1,4}/).join(" ")
    end

    def normalize_bic(value)
      value.to_s.gsub(/\s/, "").upcase
    end

    # ISO 9362: institution, country, location, optional branch. 8 or 11
    # characters, never 9 or 10 (a truncated paste).
    BIC_PATTERN = /\A[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?\z/

    def valid_bic?(value)
      normalize_bic(value).match?(BIC_PATTERN)
    end

    # The payee-name/sort-code/account-number override trio is all-or-nothing:
    # a partial set would splice a third party's details onto the payee's own.
    def overrides_incomplete?(payee_name, sort_code, account_number)
      overrides = [ payee_name, sort_code, account_number ]
      overrides.any?(&:present?) && !overrides.all?(&:present?)
    end

    # No override: the payee falls back to the submitter's own details. Right on
    # a Reimbursement, a misdirected payment on an Invoice.
    def overrides_missing?(payee_name, sort_code, account_number)
      [ payee_name, sort_code, account_number ].all?(&:blank?)
    end
  end
end
