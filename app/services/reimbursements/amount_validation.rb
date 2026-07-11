module Reimbursements
  ##
  # Server-side validation for the amount / amount-excl-VAT fields on the two
  # finance write paths (Review #save and Expense edits #update). The
  # number_field min/step attributes are client-only, so a negative or
  # non-numeric amount can still POST straight through to store.update_expense!.
  # Both controllers run this before any write and reject the request otherwise.
  #
  # - amount (gross): required to be a positive number — you can't pay £nil, £0
  #   or a negative.
  # - amount_excl_vat: optional; blank or "0" is the "not yet known" sentinel
  #   (left untouched by the save), so it's only validated when a non-zero value
  #   is given, and then it must be a positive number.
  module AmountValidation
    module_function

    # A human-readable error string when the amounts are invalid, else nil.
    def error_for(amount:, amount_excl_vat:)
      return "Enter a valid amount greater than 0." unless positive_number?(amount)

      unless blank_or_zero?(amount_excl_vat) || positive_number?(amount_excl_vat)
        return "Enter a valid amount excl. VAT greater than 0, or leave it blank."
      end

      nil
    end

    def positive_number?(raw)
      Float(raw.to_s.strip).positive?
    rescue ArgumentError, TypeError
      false
    end
    private_class_method :positive_number?

    def blank_or_zero?(raw)
      value = raw.to_s.strip
      return true if value.blank?

      Float(value).zero?
    rescue ArgumentError, TypeError
      false
    end
    private_class_method :blank_or_zero?
  end
end
