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

    def normalized_sort_code
      sort_code.to_s.gsub(/[-\s]/, "")
    end

    # Stored in Airtable in the conventional dashed form, e.g. "80-22-60"
    # (bedlam-bacs' modulus check strips the dashes itself).
    def formatted_sort_code
      digits = normalized_sort_code
      return sort_code if digits.length != 6

      digits.scan(/\d{2}/).join("-")
    end

    def normalized_account_number
      account_number.to_s.gsub(/\s/, "")
    end

    private

    def sort_code_format
      return if sort_code.blank? || normalized_sort_code.match?(/\A\d{6}\z/)

      errors.add(:sort_code, "must be 6 digits, e.g. 80-22-60.")
    end

    def account_number_format
      return if account_number.blank? || normalized_account_number.match?(/\A\d{8}\z/)

      errors.add(:account_number, "must be 8 digits.")
    end
  end
end
