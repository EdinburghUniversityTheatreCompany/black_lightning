module Reimbursements
  ##
  # Expense domain behaviour shared verbatim by the ActiveRecord Expense and
  # the Airtable-era PORO (Reimbursements::Airtable::Expense), like
  # EffectivePayee — during the cutover window both backends must answer
  # these identically. Includers provide status, expense_type, budget,
  # amount, amount_excl_vat, description, payment_reference, receipts,
  # sharepoint_receipt_urls and ai_check_status.
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
      missing << "a receipt" if receipts.empty? && sharepoint_receipt_urls.blank?
      missing
    end

    def needs_completion?
      missing_completion_fields.any?
    end

    # Attached files if any, otherwise the count of SharePoint URLs stored
    # when the files were offloaded during batch processing.
    def receipt_count
      receipts.any? ? receipts.size : sharepoint_receipt_urls.size
    end

    # True only for a genuine pass/fail verdict — "error" means the checker
    # itself couldn't run (e.g. a transient Gemini outage), so it must NOT
    # count as "already checked": that would permanently lock the expense out
    # of ever being (re)checked once the outage clears.
    def ai_checked?
      %w[pass fail].include?(ai_check_status)
    end
  end
end
