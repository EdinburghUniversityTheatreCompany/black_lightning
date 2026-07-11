module Reimbursements
  ##
  # An expense submission from the Airtable Expenses table. PORO boundary type
  # mirroring bedlam-bacs' dataclass; unlike there, +person+ and +budget+ may be
  # nil (email-in submissions can arrive with gaps the submitter fills later).
  class Expense
    TYPE_REIMBURSEMENT = "Reimbursement".freeze
    TYPE_INVOICE = "Invoice".freeze
    TYPE_FROM_EUSA = "From EUSA (utility, staff cost, etc)".freeze
    TYPES = [ TYPE_REIMBURSEMENT, TYPE_INVOICE, TYPE_FROM_EUSA ].freeze
    # "From EUSA" is internal bookkeeping; submitters only pick between these.
    SUBMITTER_TYPES = [ TYPE_REIMBURSEMENT, TYPE_INVOICE ].freeze

    attr_reader :record_id, :auto_number, :person, :amount, :amount_excl_vat, :budget,
                :description, :receipts, :status, :expense_type, :payee_name_override,
                :sort_code_override, :account_number_override, :nominal_code_override,
                :payment_reference, :rejection_reason, :submitted_at,
                :submitted_to_eusa_date, :payment_confirmed_date, :batch_id,
                :producer_notified, :receipts_offloaded, :sharepoint_receipt_urls,
                :ai_check_status, :ai_comment, :ai_checked_at

    # The trailing keyword args are operator-side fields the portal never set;
    # they default empty/nil so the portal's Mapper.expense keeps working
    # unchanged until the Mapper is extended to read them.
    def initialize(record_id:, status:, auto_number: nil, person: nil, amount: nil,
                   amount_excl_vat: nil, budget: nil, description: "", receipts: [],
                   expense_type: TYPE_REIMBURSEMENT, payee_name_override: "",
                   sort_code_override: "", account_number_override: "",
                   nominal_code_override: "", payment_reference: "", rejection_reason: "",
                   submitted_at: nil, submitted_to_eusa_date: nil, payment_confirmed_date: nil,
                   batch_id: nil, producer_notified: false, receipts_offloaded: false,
                   sharepoint_receipt_urls: [], ai_check_status: "", ai_comment: "",
                   ai_checked_at: nil)
      @record_id = record_id
      @status = status
      @auto_number = auto_number
      @person = person
      @amount = amount
      @amount_excl_vat = amount_excl_vat
      @budget = budget
      @description = description
      @receipts = receipts
      @expense_type = expense_type
      @payee_name_override = payee_name_override
      @sort_code_override = sort_code_override
      @account_number_override = account_number_override
      @nominal_code_override = nominal_code_override
      @payment_reference = payment_reference
      @rejection_reason = rejection_reason
      @submitted_at = submitted_at
      @submitted_to_eusa_date = submitted_to_eusa_date
      @payment_confirmed_date = payment_confirmed_date
      @batch_id = batch_id
      @producer_notified = producer_notified
      @receipts_offloaded = receipts_offloaded
      @sharepoint_receipt_urls = sharepoint_receipt_urls
      @ai_check_status = ai_check_status
      @ai_comment = ai_comment
      @ai_checked_at = ai_checked_at
    end

    def pending?
      status == Status::PENDING
    end

    def draft?
      status == Status::DRAFT
    end

    # Submitters may only change an expense before review picks it up, and
    # never internal "From EUSA" bookkeeping entries (editing one in the
    # portal would silently rewrite its type to a submitter type).
    def editable?
      (draft? || pending?) && Expense::SUBMITTER_TYPES.include?(expense_type)
    end

    # Human labels for the required fields still missing on an incomplete
    # (usually email-in) submission, so the UI can tell the submitter exactly
    # what to add rather than a bare "needs completion".
    def missing_completion_fields
      missing = []
      missing << "a budget" if budget.nil?
      missing << "the amount" if amount.blank?
      missing << "the amount excluding VAT" if amount_excl_vat.blank?
      missing << "a description" if description.blank?
      missing << "a payment reference" if payment_reference.blank?
      # A receipt counts as present if a file is attached OR a SharePoint URL was
      # stored when it was offloaded during batch processing (which clears the
      # Airtable attachment).
      missing << "a receipt" if receipts.empty? && sharepoint_receipt_urls.blank?
      missing
    end

    # True when the submission is missing fields the portal form requires, so the
    # index can nudge the submitter.
    def needs_completion?
      missing_completion_fields.any?
    end

    def payee_override?
      payee_name_override.present? || sort_code_override.present? ||
        account_number_override.present?
    end

    # --- Effective payee (the money path) ---------------------------------
    # For an Invoice the submitter can override payee name + bank details so
    # EUSA pays a third party directly. The BACS row, modulus check and
    # "needs attention" use these effective values; notification emails stay
    # with the linked person (see notifications). Mirrors bedlam-bacs.

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
