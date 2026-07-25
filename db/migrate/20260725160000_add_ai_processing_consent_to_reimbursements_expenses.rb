class AddAiProcessingConsentToReimbursementsExpenses < ActiveRecord::Migration[8.1]
  # One consent, two purposes: reading the receipt to prefill the submission
  # form, and later sending it to Gemini again so the finance AI check can
  # compare it against the claim. The submitter answers once, on the receipt
  # form, and that answer governs both.
  #
  # Deliberately a NULLABLE boolean with no default, because three states are
  # meaningfully different and only two of them are the same decision:
  #   true  - the submitter consented (self or invoice mode)
  #   false - the submitter declined ("No, I will fill in all the details myself")
  #   nil   - nobody was ever asked (every claim submitted before this shipped,
  #           and every email-in claim, where no submitter is present to ask)
  # Both falsey states block the AI check; keeping them distinct is what lets
  # the finance UI say "declined" rather than "never asked" honestly.
  #
  # No backfill: nil is exactly the right value for existing rows. Verdicts
  # already written stay put — this column governs future checks only.
  def change
    add_column :reimbursements_expenses, :ai_processing_consent, :boolean
  end
end
