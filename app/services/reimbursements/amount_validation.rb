module Reimbursements
  ##
  # Server-side amount checks for the two finance write paths (Review #save and
  # expense edits #update), read through AmountParser. Blank or "0" excl-VAT is
  # the "not yet known" sentinel.
  module AmountValidation
    # Fat-finger ceiling (an extra digit reaching a live BACS request); also
    # catches scientific notation such as "1e10".
    MAX_AMOUNT = 100_000

    module_function

    # An error string, or nil when the amounts are fine.
    def error_for(amount:, amount_excl_vat:)
      gross = AmountParser.parse(amount)
      return "Enter a valid amount greater than 0." unless payable?(gross)

      net = AmountParser.parse(amount_excl_vat)
      if amount_excl_vat.present? && !net&.zero? && !payable?(net)
        return "Enter a valid amount excl. VAT greater than 0, or leave it blank."
      end

      # An excl-VAT above gross skews the over-budget check and reconciliation.
      if payable?(net) && net > gross
        return "Amount excl. VAT can't be more than the total amount."
      end

      nil
    end

    # The value to WRITE: AR casts a string to a decimal column with to_d, so
    # the raw "£1,200" would store 0.
    def amount(raw)
      AmountParser.parse(raw)
    end

    # nil means leave the stored value alone.
    def amount_excl_vat(raw)
      parsed = AmountParser.parse(raw)
      parsed if parsed&.positive?
    end

    def payable?(value)
      !value.nil? && value.positive? && value <= MAX_AMOUNT
    end
    private_class_method :payable?
  end
end
