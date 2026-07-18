module Reimbursements
  module Airtable
    ##
    # An expense submission from the Airtable Expenses table. PORO boundary type
    # mirroring bedlam-bacs' dataclass; unlike there, +person+ and +budget+ may be
    # nil (email-in submissions can arrive with gaps the submitter fills later).
    class Expense
      include EffectivePayee
      include ExpenseSemantics

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
                  :ai_check_status, :ai_comment, :ai_checked_at, :rejection_notified

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
                     ai_checked_at: nil, rejection_notified: nil)
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
        @rejection_notified = rejection_notified
      end
    end
  end
end
