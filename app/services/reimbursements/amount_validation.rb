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
    # A plain decimal number: optional leading minus, digits, optional
    # fractional part. Deliberately stricter than Kernel#Float alone (which
    # happily accepts "0x1A" as hex, or "1e10" as scientific notation) — a
    # value that passes this can never diverge between Float() (used here)
    # and String#to_f (used by the actual write path, Mapper#expense_fields),
    # since the two only disagree on inputs this format already excludes.
    DECIMAL_FORMAT = /\A-?\d+(\.\d+)?\z/

    # A generous sanity ceiling — no real Bedlam Fringe expense claim is ever
    # going to be six figures. Catches a fat-finger typo (an extra digit, a
    # missing decimal point) that would otherwise sail all the way through to
    # a live BACS payment request with no other server-side backstop.
    MAX_AMOUNT = 100_000

    module_function

    # A human-readable error string when the amounts are invalid, else nil.
    def error_for(amount:, amount_excl_vat:)
      return "Enter a valid amount greater than 0." unless positive_number?(amount)

      unless blank_or_zero?(amount_excl_vat) || positive_number?(amount_excl_vat)
        return "Enter a valid amount excl. VAT greater than 0, or leave it blank."
      end

      # Matches the submitter-facing ExpenseForm's amounts_valid, which already
      # rejects this — the finance write paths (Review#save,
      # ExpenseEditsController#update) previously didn't, so an edit here
      # could silently skew the over-budget check and reconciliation matching.
      if positive_number?(amount_excl_vat) && parse(amount_excl_vat) > parse(amount)
        return "Amount excl. VAT can't be more than the total amount."
      end

      nil
    end

    def positive_number?(raw)
      value = raw.to_s.strip
      return false unless value.match?(DECIMAL_FORMAT)

      parsed = Float(value)
      parsed.positive? && parsed <= MAX_AMOUNT
    rescue ArgumentError, TypeError
      false
    end
    private_class_method :positive_number?

    def parse(raw)
      Float(raw.to_s.strip)
    end
    private_class_method :parse

    def blank_or_zero?(raw)
      value = raw.to_s.strip
      return true if value.blank?

      value.match?(DECIMAL_FORMAT) && Float(value).zero?
    rescue ArgumentError, TypeError
      false
    end
    private_class_method :blank_or_zero?
  end
end
