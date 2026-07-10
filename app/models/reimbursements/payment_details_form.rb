module Reimbursements
  ##
  # Form object for a submitter's payee name and UK bank details, written to
  # their Airtable People record. bedlam-bacs gates approval on these (and
  # runs the full modulus check there); the portal validates format only.
  class PaymentDetailsForm
    include ActiveModel::Model

    attr_accessor :name, :sort_code, :account_number

    validates :name, :sort_code, :account_number, presence: true
    validate :sort_code_format
    validate :account_number_format

    def formatted_sort_code
      BankDetails.format_sort_code(sort_code)
    end

    def normalized_account_number
      BankDetails.normalize_account_number(account_number)
    end

    private

    def sort_code_format
      return if sort_code.blank? || BankDetails.valid_sort_code?(sort_code)

      errors.add(:sort_code, BankDetails::SORT_CODE_HINT)
    end

    def account_number_format
      return if account_number.blank? || BankDetails.valid_account_number?(account_number)

      errors.add(:account_number, BankDetails::ACCOUNT_NUMBER_HINT)
    end
  end
end
