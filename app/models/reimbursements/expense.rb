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
                :sort_code_override, :account_number_override, :payment_reference,
                :rejection_reason, :submitted_at

    def initialize(record_id:, status:, auto_number: nil, person: nil, amount: nil,
                   amount_excl_vat: nil, budget: nil, description: "", receipts: [],
                   expense_type: TYPE_REIMBURSEMENT, payee_name_override: "",
                   sort_code_override: "", account_number_override: "",
                   payment_reference: "", rejection_reason: "", submitted_at: nil)
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
      @payment_reference = payment_reference
      @rejection_reason = rejection_reason
      @submitted_at = submitted_at
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

    # True when an email-in (or otherwise incomplete) submission is missing
    # fields the portal form requires, so the index can nudge the submitter.
    def needs_completion?
      budget.nil? || amount.blank? || amount_excl_vat.blank? ||
        description.blank? || payment_reference.blank? || receipts.empty?
    end

    def payee_override?
      payee_name_override.present? || sort_code_override.present? ||
        account_number_override.present?
    end
  end
end
