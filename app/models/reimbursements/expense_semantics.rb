module Reimbursements
  ##
  # Expense domain predicates.
  module ExpenseSemantics
    def pending? = status == Status::PENDING
    def draft? = status == Status::DRAFT
    def approved? = status == Status::APPROVED

    # Never internal "From EUSA" entries: editing one in the portal would
    # rewrite its type to a submitter type.
    def editable?
      (draft? || pending?) && self.class::SUBMITTER_TYPES.include?(expense_type)
    end

    # A zero amount means "not yet known" (.blank? misses it).
    def missing_completion_fields
      missing = []
      missing << "a budget" if budget.nil?
      missing << "the amount" if amount.blank? || amount.zero?
      missing << "the amount excluding VAT" if amount_excl_vat.blank? || amount_excl_vat.zero?
      missing << "a description" if description.blank?
      missing << "a payment reference" if payment_reference.blank?
      # A SharePoint URL stored when the file was offloaded counts as a receipt.
      missing << "a receipt" if receipt_files.empty? && sharepoint_receipt_urls.blank?
      missing
    end

    def needs_completion?
      missing_completion_fields.any?
    end

    # Counts the attachments rather than building #receipts (three route
    # paths per file) for every row; falls back to offloaded SharePoint URLs.
    def receipt_count
      attached = receipt_files.size
      attached.positive? ? attached : sharepoint_receipt_urls.size
    end
  end
end
