module Reimbursements
  ##
  # The effective-payee money path, split out of Expense.
  #
  # For an Invoice the submitter can override payee name and bank details so
  # EUSA pays a third party. The BACS row, modulus check and "needs attention"
  # use these values; notification emails stay with the linked person.
  module EffectivePayee
    def payee_override?
      payee_name_override.present? || sort_code_override.present? ||
        account_number_override.present?
    end

    def effective_payee_name
      payee_name_override.to_s.strip.presence || person&.name.to_s
    end

    def effective_sort_code
      sort_code_override.to_s.strip.presence || person&.sort_code.to_s
    end

    def effective_account_number
      account_number_override.to_s.strip.presence || person&.account_number.to_s
    end

    def effective_iban
      iban_override.to_s.strip.presence || person&.iban.to_s
    end

    def effective_bic
      bic_override.to_s.strip.presence || person&.bic.to_s
    end

    # Whether we know where to send the money, asked of the claim's own rail.
    # Reading the UK pair for an international claim made every one permanently
    # unapprovable (ReviewController#approve_blocker refuses on this).
    # An IBAN alone is not enough: EUSA's bank needs the BIC too to route it.
    def effective_has_bank_details?
      return effective_iban.present? && effective_bic.present? if international?

      effective_sort_code.present? && effective_account_number.present?
    end

    # Nominal code for the BACS spreadsheet: the override, else the budget's.
    def effective_nominal_code
      nominal_code_override.to_s.strip.presence || budget&.nominal_code.to_s
    end
  end
end
