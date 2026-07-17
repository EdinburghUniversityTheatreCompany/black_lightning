module Admin
  module Reimbursements
    ##
    # A budget owner's view of the budgets they're responsible for and the
    # pending expenses charged to them awaiting their sign-off. Gated by the
    # base +:access, :reimbursements+ permission (inherited from BaseController),
    # so an owner who isn't on the finance team can still endorse — the blocking
    # gate the finance Review queue then honours.
    class MyBudgetsController < BaseController
      def index
        @title = "My Budgets"
        @budgets = owned_budgets
        owned_ids = @budgets.map(&:record_id).to_set
        pending = store.expenses.select do |expense|
          expense.status == ::Reimbursements::Status::PENDING &&
            owned_ids.include?(expense.budget&.record_id)
        end
        @expenses_by_budget = pending.group_by { |expense| expense.budget.record_id }
        @endorsements_by_expense = ::Reimbursements::OwnerEndorsement
          .where(expense_record_id: pending.map(&:record_id)).index_by(&:expense_record_id)
        @people_by_id = store.people.index_by(&:record_id)
      end

      # Record this owner's endorsement of a pending expense on one of their
      # budgets — the sign-off finance needs before approving it.
      def endorse
        expense = store.find_expense!(params[:expense_id])
        unless ::Reimbursements::OwnerReview.owned_by?(expense, current_person)
          redirect_to admin_reimbursements_my_budgets_path,
                      alert: "You can only endorse expenses on budgets you own."
          return
        end

        ::Reimbursements::OwnerEndorsement.find_or_create_by!(expense_record_id: expense.record_id) do |endorsement|
          endorsement.budget_record_id = expense.budget.record_id
          endorsement.endorsed_by_person_id = current_person.record_id
          endorsement.endorsed_at = Time.current
        end
        redirect_to admin_reimbursements_my_budgets_path,
                    notice: "Thanks — you've endorsed this claim for the finance team."
      rescue ActiveRecord::RecordNotUnique
        # Another owner endorsed a moment ago; the gate is satisfied either way.
        redirect_to admin_reimbursements_my_budgets_path, notice: "Already endorsed by another owner."
      end

      private

      def owned_budgets
        return [] if current_person.nil?

        ::Reimbursements::OwnerReview.owned_budgets(store.active_budgets, current_person)
      end
    end
  end
end
