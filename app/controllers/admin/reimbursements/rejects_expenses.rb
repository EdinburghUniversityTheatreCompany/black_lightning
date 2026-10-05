module Admin
  module Reimbursements
    ##
    # Reject a Pending or Approved expense with a reason and email the payee.
    # Shared by finance Review and a budget owner, so the submitter's experience
    # does not depend on who rejected it.
    module RejectsExpenses
      extend ActiveSupport::Concern
      include ::ErrorReporting

      private

      def reject_expense(expense, reason)
        return :skipped_wrong_status unless expense.pending? || expense.approved?

        attrs = { status: ::Reimbursements::Status::REJECTED, rejection_reason: reason }
        notified = notify_rejection(expense, reason)
        attrs[:rejection_notified] = Time.current if notified
        store.update_expense!(expense.record_id, attrs)
        notified
      end

      # Sent from the claim's own cost centre's mailbox. A failed send returns
      # false, leaving rejection_notified unstamped, and never blocks the rejection.
      def notify_rejection(expense, reason)
        email = expense.person&.email
        return false if email.blank?

        notifier_for(expense.cost_centre).rejection(
          to: email,
          greeting_name: ::Reimbursements::GreetingName.for(expense.person),
          auto_number: expense.auto_number,
          amount: expense.amount.to_f,
          budget_name: expense.budget&.display_name.to_s,
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
