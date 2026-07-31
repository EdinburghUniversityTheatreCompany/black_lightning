module Reimbursements
  ##
  # Expense domain predicates, split out of the model to keep it readable.
  # Includers provide status, expense_type, budget, amount, amount_excl_vat,
  # description, payment_reference, receipt_files and sharepoint_receipt_urls.
  module ExpenseSemantics
    def pending? = status == Status::PENDING
    def draft? = status == Status::DRAFT
    def approved? = status == Status::APPROVED

    # Submitters may only change an expense before review picks it up, and
    # never internal "From EUSA" bookkeeping entries (editing one in the
    # portal would silently rewrite its type to a submitter type).
    def editable?
      (draft? || pending?) && self.class::SUBMITTER_TYPES.include?(expense_type)
    end

    # Human labels for the required fields still missing on an incomplete
    # (usually email-in) submission. A documented zero amount means "not yet
    # known" — .blank? alone would miss it (0 is truthy in Ruby).
    def missing_completion_fields
      missing = []
      missing << "a budget" if budget.nil?
      missing << "the amount" if amount.blank? || amount.zero?
      missing << "the amount excluding VAT" if amount_excl_vat.blank? || amount_excl_vat.zero?
      missing << "a description" if description.blank?
      missing << "a payment reference" if payment_reference.blank?
      # A receipt counts as present if a file is attached OR a SharePoint URL
      # was stored when it was offloaded during batch processing.
      missing << "a receipt" if receipt_files.empty? && sharepoint_receipt_urls.blank?
      missing
    end

    def needs_completion?
      missing_completion_fields.any?
    end

    # Attached files if any, otherwise the count of SharePoint URLs stored
    # when the files were offloaded during batch processing.
    #
    # Counts the attachments, NOT the wrapped #receipts: each wrapper mints a signed id,
    # a blob path and a variant representation path, and this is asked once per row on the
    # batch-builder and expense-edit screens — a lot of URL signing to answer "how many?".
    def receipt_count
      attached = receipt_files.size
      attached.positive? ? attached : sharepoint_receipt_urls.size
    end
  end
end
