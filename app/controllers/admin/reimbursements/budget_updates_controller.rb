module Admin
  module Reimbursements
    ##
    # Multi-budget forecast revisions. One "budget update" captures a shared
    # effective date + note (e.g. the outcome of a budget meeting) and logs a
    # new forecast for each budget whose amount the operator filled in — blanks
    # are skipped. Each created forecast links back to the update, and the
    # per-budget forecast log surfaces the shared note.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController.
    class BudgetUpdatesController < FinanceController
      def index
        @title = "Budget updates"
        @budget_updates = store.budget_updates
        @budgets_by_id = store.budgets.index_by(&:record_id)
      end

      def new
        @title = "New budget update"
        @effective_date = parse_date(params[:effective_date]) || Date.current
        @budgets = active_budgets_for_update
      end

      def create
        effective_date = parse_date(params[:effective_date])
        entries = forecast_entries
        if effective_date.nil?
          return redirect_to(new_admin_reimbursements_budget_update_path, alert: "Enter a valid effective date.")
        end
        if entries.empty?
          return redirect_to(new_admin_reimbursements_budget_update_path,
                             alert: "Enter a new amount for at least one budget.")
        end

        store.create_budget_update!(effective_date: effective_date, note: params[:note].to_s,
                                    created_by: current_user, forecasts: entries)
        redirect_to admin_reimbursements_budget_updates_path,
                    notice: "Budget update saved — #{pluralize_forecasts(entries.size)} logged."
      end

      private

      # Active budgets (income included — they carry forecasts too), named for a
      # deterministic form order.
      def active_budgets_for_update
        store.budgets.select(&:active).sort_by { |b| b.name.to_s.downcase }
      end

      # One {budget_id:, amount:} per budget whose amount field was filled with a
      # valid number; blank or malformed amounts are dropped so an operator can
      # revise a subset in one pass. The keys are dynamic budget ids, so read the
      # nested hash directly rather than strong-param whitelisting each id.
      def forecast_entries
        amounts = params[:amounts]
        return [] if amounts.blank?

        amounts.to_unsafe_h.filter_map do |budget_id, raw|
          amount = parse_decimal(raw)
          next if amount.nil?

          { budget_id: budget_id.to_s, amount: amount }
        end
      end

      def pluralize_forecasts(count)
        helpers.pluralize(count, "forecast")
      end

      def parse_decimal(value)
        return nil if value.blank?

        BigDecimal(value.to_s)
      rescue ArgumentError
        nil
      end

      def parse_date(value)
        return nil if value.blank?

        Date.parse(value.to_s)
      rescue Date::Error
        nil
      end
    end
  end
end
