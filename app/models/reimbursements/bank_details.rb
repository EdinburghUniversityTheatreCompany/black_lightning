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

    # --- International (IBAN / BIC) -----------------------------------------
    #
    # The international rail carries an IBAN and a BIC instead of a sort code
    # and account number. Only SPACES are stripped: they are the noise a human
    # adds reading a number off an invoice, whereas a hyphen or a dot means the
    # value came from somewhere unexpected and should be looked at rather than
    # silently cleaned.

    def normalize_iban(value)
      value.to_s.gsub(/\s/, "").upcase
    end

    # Two letters (country), two check digits, then 11-30 alphanumerics.
    IBAN_PATTERN = /\A[A-Z]{2}\d{2}[A-Z0-9]{11,30}\z/

    # The ISO 13616 mod-97 check. This is the whole point of validating an IBAN
    # at all: the realistic error is a transposed or dropped character in a
    # 22-34 character string nobody reads back, and a wrong IBAN that passes a
    # mere shape check is money sent somewhere unrecoverable. A shape check
    # alone would accept 99% of typos.
    def valid_iban?(value)
      iban = normalize_iban(value)
      return false unless iban.match?(IBAN_PATTERN)

      # Move the country code and check digits to the end, then read every
      # letter as its 0-based position in the alphabet plus 10 (A = 10, Z = 35).
      rearranged = iban[4..] + iban[0, 4]
      digits = rearranged.each_char.map { |char| char.match?(/[A-Z]/) ? (char.ord - 55).to_s : char }.join
      digits.to_i % 97 == 1
    end

    # Grouped in fours for display, the convention every bank prints. An
    # unparseable value is returned untouched rather than mangled into groups,
    # so a half-typed IBAN on a re-rendered form still reads as what was typed.
    def format_iban(value)
      return value unless valid_iban?(value)

      normalize_iban(value).scan(/.{1,4}/).join(" ")
    end

    # An IBAN reduced to its country and last four CHARACTERS, for exports and
    # audit lines. Not BankDetails.mask: that strips non-digits, and some
    # countries' IBANs end in letters (a Seychelles IBAN ends with a currency
    # code), so it would mask the wrong end. The country prefix is kept because
    # it is not identifying and tells a reader which rail the payment took.
    def mask_iban(value)
      iban = normalize_iban(value)
      return "" if iban.empty?

      "#{iban[0, 2]}****#{iban[-4..] || iban}"
    end

    def normalize_bic(value)
      value.to_s.gsub(/\s/, "").upcase
    end

    # ISO 9362: four letters (institution), two letters (country), two
    # alphanumerics (location), and optionally three more (branch). 8 or 11
    # characters — never 9 or 10, which is the tell of a truncated paste.
    BIC_PATTERN = /\A[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?\z/

    def valid_bic?(value)
      normalize_bic(value).match?(BIC_PATTERN)
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
