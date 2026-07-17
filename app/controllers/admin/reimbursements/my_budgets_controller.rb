module Admin
  module Reimbursements
    ##
    # A budget owner's view of the budgets they're responsible for and the
    # pending claims charged to them awaiting their sign-off. Gated by the base
    # +:access, :reimbursements+ permission (inherited from BaseController), so an
    # owner who isn't on the finance team can still act. An owner can endorse a
    # claim (the blocking gate the finance Review queue honours), withdraw an
    # endorsement they gave in error, or reject a claim outright with a reason.
    class MyBudgetsController < BaseController
      include RejectsExpenses

      def index
        @title = "My Budgets"
        # Own from the FULL budget list, not just active ones: a budget can be
        # deactivated while a claim against it is still Pending, and that claim
        # keeps blocking finance — the owner must still be able to act on it.
        all_owned = owned_budgets
        owned_ids = all_owned.map(&:record_id).to_set
        pending = store.expenses.select do |expense|
          expense.status == ::Reimbursements::Status::PENDING &&
            owned_ids.include?(expense.budget&.record_id)
        end
        @expenses_by_budget = pending.group_by { |expense| expense.budget.record_id }
        # Show active expense budgets, plus any (even inactive) owned budget that
        # still has a pending claim needing sign-off, so none is stranded. Ones
        # with claims come first so a many-budget owner sees the work up top.
        @budgets = all_owned
          .select { |budget| (budget.active && !budget.income?) || @expenses_by_budget.key?(budget.record_id) }
          .sort_by { |budget| [ @expenses_by_budget.key?(budget.record_id) ? 0 : 1, budget.name.to_s.downcase ] }
        @pending_count = pending.size
        @endorsements_by_expense = ::Reimbursements::OwnerEndorsement
          .where(expense_record_id: pending.map(&:record_id)).index_by(&:expense_record_id)
        @people_by_id = store.people.index_by(&:record_id)
      end

      # Record this owner's endorsement of a pending claim on one of their
      # budgets — the sign-off finance needs before approving it.
      def endorse
        expense = owned_pending_expense
        return unless expense

        # Upsert (not find_or_create): if a stale row exists from a since-edited
        # claim, refresh its snapshot so the sign-off covers the CURRENT terms.
        endorsement = ::Reimbursements::OwnerEndorsement.for_expense(expense.record_id).first_or_initialize
        endorsement.assign_attributes(
          budget_record_id: expense.budget.record_id,
          endorsed_by_person_id: current_person.record_id,
          overridden_by: nil,
          endorsed_amount: expense.amount,
          endorsed_at: Time.current
        )
        endorsement.save!
        redirect_to_my_budgets(notice: "Thanks, you've endorsed this claim for the finance team.")
      rescue ActiveRecord::RecordNotUnique
        # Another owner endorsed a moment ago; the gate is satisfied either way.
        redirect_to_my_budgets(notice: "Already endorsed by another owner.")
      end

      # Undo an endorsement given in error, while the claim is still Pending —
      # re-blocking finance until it's endorsed (or overridden) again.
      def withdraw
        expense = owned_pending_expense
        return unless expense

        ::Reimbursements::OwnerEndorsement.for_expense(expense.record_id).delete_all
        redirect_to_my_budgets(notice: "Withdrawn. This claim is back to awaiting sign-off.")
      end

      # Reject a claim on an owned budget outright, with a reason emailed to the
      # submitter (same state change + email as a finance rejection).
      def reject
        expense = owned_pending_expense
        return unless expense

        reason = params[:rejection_reason].to_s.strip
        if reason.blank?
          redirect_to_my_budgets(alert: "Please give a reason so the submitter knows why.")
          return
        end

        reject_expense(expense, reason)
        redirect_to_my_budgets(notice: "Rejected ##{expense.auto_number} and let the submitter know.")
      end

      private

      # The pending claim named by params[:expense_id], but only if the signed-in
      # owner owns its budget and it's still Pending. Redirects and returns nil
      # otherwise so the caller can `return unless`.
      def owned_pending_expense
        expense = store.find_expense!(params[:expense_id])
        unless ::Reimbursements::OwnerReview.owned_by?(expense, current_person)
          redirect_to_my_budgets(alert: "You can only act on claims charged to budgets you own.")
          return nil
        end
        unless expense.pending?
          redirect_to_my_budgets(alert: "##{expense.auto_number} is no longer Pending, so there is nothing to do.")
          return nil
        end
        expense
      end

      def owned_budgets
        return [] if current_person.nil?

        ::Reimbursements::OwnerReview.owned_budgets(store.budgets, current_person)
      end

      def redirect_to_my_budgets(flash)
        redirect_to admin_reimbursements_my_budgets_path, **flash
      end
    end
  end
end
