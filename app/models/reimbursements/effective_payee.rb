module Reimbursements
  ##
  # The effective-payee money path, shared verbatim by the ActiveRecord
  # Expense and the Airtable-era PORO (Reimbursements::Airtable::Expense) so
  # both backends compute BACS rows identically during the cutover window.
  #
  # For an Invoice the submitter can override payee name + bank details so
  # EUSA pays a third party directly. The BACS row, modulus check and
  # "needs attention" use these effective values; notification emails stay
  # with the linked person. Mirrors bedlam-bacs.
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

    def effective_has_bank_details?
      effective_sort_code.present? && effective_account_number.present?
    end

    # Nominal code that actually hits the BACS spreadsheet: an explicit
    # override wins, else the linked budget's code.
    def effective_nominal_code
      nominal_code_override.to_s.strip.presence || budget&.nominal_code.to_s
    end
  end
end
