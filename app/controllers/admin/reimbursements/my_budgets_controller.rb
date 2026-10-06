module Admin
  module Reimbursements
    ##
    # A budget owner's view of their budgets and the pending claims awaiting their sign-off.
    # Gated by the base `:access, :reimbursements` permission, so an owner outside the finance
    # team can still endorse a claim, withdraw an endorsement, or reject a claim with a reason.
    class MyBudgetsController < BaseController
      include RejectsExpenses

      def index
        @title = "My Budgets"
        # Own from the FULL budget list, not just active ones: a deactivated budget can still
        # hold a Pending claim that blocks finance.
        all_owned = ::Reimbursements::OwnerReview.owned_budgets(store.budgets, current_person)
        owned_ids = all_owned.map(&:record_id).to_set
        @pending = store.expenses.select do |expense|
          expense.status == ::Reimbursements::Status::PENDING &&
            owned_ids.include?(expense.budget&.record_id)
        end.sort_by { |expense| expense.submitted_at || Time.zone.now }
        @rows = owned_rows(all_owned)
        @endorsements_by_expense = ::Reimbursements::OwnerEndorsement
          .where(expense_record_id: @pending.map(&:record_id)).index_by(&:expense_record_id)
        @people_by_id = store.people.index_by(&:record_id)
      end

      def endorse
        expense = owned_pending_expense
        return unless expense

        # Upsert, not find_or_create: a stale row from a since-edited claim is refreshed so the
        # sign-off covers the CURRENT terms.
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

      # Re-blocks finance until the claim is endorsed (or overridden) again.
      def withdraw
        expense = owned_pending_expense
        return unless expense

        ::Reimbursements::OwnerEndorsement.for_expense(expense.record_id).delete_all
        redirect_to_my_budgets(notice: "Withdrawn. This claim is back to awaiting sign-off.")
      end

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

      # Redirects and returns nil unless the signed-in owner owns the claim's budget and it is
      # still Pending.
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

      # An AREA where they own the show, a loose line where they own the line itself. Rows with
      # claims waiting sort first.
      #
      # Area figures must come off store.areas (preloaded); reading them off budget.area N+1s.
      def owned_rows(all_owned)
        # area_id is the raw integer FK while record_id is a string, so they only match once cast.
        area_ids = all_owned.filter_map { |budget| budget.area_id&.to_s }.to_set
        areas = store.areas.select { |area| area_ids.include?(area.record_id) }
        loose = all_owned.select { |budget| budget.area_id.nil? && (budget.active || waiting_on?(budget)) }

        rows = areas.map { |area| area_row(area) } + loose.map { |budget| loose_row(budget) }
        rows.sort_by { |row| [ row[:waiting_count].positive? ? 0 : 1, row[:name].to_s.downcase ] }
      end

      def area_row(area)
        { name: area.name, scope: scope_label(area),
          detail: "#{area.budgets.size} #{'line'.pluralize(area.budgets.size)}",
          summary: ::Reimbursements::SpendSummary.for_area(area),
          waiting_count: area.budgets.count { |line| waiting_on?(line) },
          path: admin_reimbursements_area_path(area.record_id) }
      end

      def loose_row(budget)
        { name: budget.name, scope: scope_label(budget),
          detail: "a single budget, in no area",
          summary: ::Reimbursements::SpendSummary.for_budget(budget),
          waiting_count: waiting_count(budget),
          path: admin_reimbursements_budget_path(budget.record_id) }
      end

      def waiting_count(budget)
        @pending.count { |expense| expense.budget&.record_id == budget.record_id }
      end

      def waiting_on?(budget) = waiting_count(budget).positive?

      def scope_label(record)
        [ record.cost_centre&.name, record.financial_year&.label ].compact.uniq.join(" · ")
      end

      def redirect_to_my_budgets(flash)
        redirect_to admin_reimbursements_my_budgets_path, **flash
      end
    end
  end
end
