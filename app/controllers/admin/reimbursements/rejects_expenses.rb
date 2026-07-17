module Admin
  module Reimbursements
    ##
    # Reject an expense (Pending or Approved) with a reason and best-effort
    # notify the payee. Shared by the finance Review queue and a budget owner
    # rejecting a claim on their own budget — same state change, same email, so
    # the submitter's experience doesn't depend on who rejected it. A send
    # failure never blocks the rejection (the operator/owner follows up).
    module RejectsExpenses
      extend ActiveSupport::Concern
      include ::Reimbursements::ErrorReporting

      private

      def reject_expense(expense, reason)
        return :skipped_wrong_status unless expense.pending? || expense.approved?

        attrs = { status: ::Reimbursements::Status::REJECTED, rejection_reason: reason }
        notified = notify_rejection(expense, reason)
        attrs[:rejection_notified] = Time.current if notified
        store.update_expense!(expense.record_id, attrs)
        notified
      end

      # Send the rejection via Graph (from the cost centre's send mailbox), but
      # never let a send failure block the rejection itself: a failed send just
      # returns false so the caller leaves rejection_notified unstamped.
      def notify_rejection(expense, reason)
        email = expense.person&.email
        return false if email.blank?

        notifier.rejection(
          to: email,
          payee_name: expense.person.name,
          auto_number: expense.auto_number,
          amount: expense.amount.to_f,
          budget_name: expense.budget&.name.to_s,
          description: expense.description.to_s,
          reason: reason
        )
        true
      rescue StandardError => e
        log_and_notify("Reimbursements: rejection email failed for ##{expense.auto_number} — #{e.message}", e,
                       context: { source: "reimbursements_rejection_email", expense: expense.auto_number })
        false
      end
    end
  end
end
