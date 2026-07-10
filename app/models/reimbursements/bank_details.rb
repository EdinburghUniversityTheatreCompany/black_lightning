module Reimbursements
  ##
  # Shared UK bank-detail rules for the portal forms. Sort codes are stored
  # in the conventional dashed form ("80-22-60") — bedlam-bacs' modulus check
  # strips the dashes itself.
  module BankDetails
    SORT_CODE_HINT = "must be 6 digits, e.g. 80-22-60.".freeze
    ACCOUNT_NUMBER_HINT = "must be 8 digits.".freeze

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
  end
end
