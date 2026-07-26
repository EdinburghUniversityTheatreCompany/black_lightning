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
  #
  # Reading is delegated to AmountParser, the same lenient parser the submitter
  # form and the budget forms use, so "£1,200" and the comma decimal "12,50" mean
  # here what they mean everywhere else in the portal. This module used to do its
  # own stricter `Float()` reading of a plain-decimal regexp, because the write
  # path then re-read the RAW STRING with `to_f` and the two could disagree — the
  # divergence is gone now that callers write #amount / #amount_excl_vat, which
  # hand back the very BigDecimal that was validated. Nothing re-parses.
  module AmountValidation
    # A generous sanity ceiling — no real Bedlam Fringe expense claim is ever
    # going to be six figures. Catches a fat-finger typo (an extra digit, a
    # missing decimal point) that would otherwise sail all the way through to
    # a live BACS payment request with no other server-side backstop. It also
    # rejects anything that read as an absurd number for a different reason,
    # e.g. scientific notation ("1e10").
    MAX_AMOUNT = 100_000

    module_function

    # A human-readable error string when the amounts are invalid, else nil.
    def error_for(amount:, amount_excl_vat:)
      gross = AmountParser.parse(amount)
      return "Enter a valid amount greater than 0." unless payable?(gross)

      net = AmountParser.parse(amount_excl_vat)
      unless blank_or_zero?(amount_excl_vat) || payable?(net)
        return "Enter a valid amount excl. VAT greater than 0, or leave it blank."
      end

      # Matches the submitter-facing ExpenseForm's amounts_valid, which already
      # rejects this — the finance write paths (Review#save,
      # ExpenseEditsController#update) previously didn't, so an edit here
      # could silently skew the over-budget check and reconciliation matching.
      if payable?(net) && net > gross
        return "Amount excl. VAT can't be more than the total amount."
      end

      nil
    end

    # The gross amount to WRITE, once #error_for has passed: the parsed
    # BigDecimal, never the raw string. ActiveRecord casts a string to a decimal
    # column with String#to_d, which reads "£1,200" as 0 — so handing the raw
    # field through would turn an amount this module just accepted into a zero
    # payment.
    def amount(raw)
      AmountParser.parse(raw)
    end

    # The excl-VAT amount to write, or nil to leave the stored value alone:
    # blank and 0 are both the "not yet known" sentinel.
    def amount_excl_vat(raw)
      parsed = AmountParser.parse(raw)
      parsed if parsed&.positive?
    end

    # Readable as money and within the sanity ceiling.
    def payable?(value)
      !value.nil? && value.positive? && value <= MAX_AMOUNT
    end
    private_class_method :payable?

    def blank_or_zero?(raw)
      return true if raw.to_s.strip.blank?

      AmountParser.parse(raw)&.zero? || false
    end
    private_class_method :blank_or_zero?
  end
end
