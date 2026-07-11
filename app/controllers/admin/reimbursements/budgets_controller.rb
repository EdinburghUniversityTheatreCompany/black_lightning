module Admin
  module Reimbursements
    ##
    # Finance-team management of the Airtable Budgets table: an overview of every
    # budget's financials (initial, rolled-up current forecast, committed, total
    # paid, remaining, variance), an edit form for the operator-editable fields
    # (name, nominal code, visible-to-submitters, notes, initial budget, budget
    # type and the many-to-many People owners), and a forecast-history log with
    # an "add a projected-spend update" action that appends a Budget Forecasts
    # record.
    #
    # Rollups/formulas (current_forecast, committed_amount, total_paid,
    # remaining, variance) are read-only displays — Airtable computes them.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController.
    class BudgetsController < FinanceController
      before_action :set_budget, only: %i[edit update forecast]

      def index
        @title = "Reimbursements Budgets"
        @budgets = store.budgets.sort_by { |budget| budget.name.to_s.downcase }
        @people_by_id = store.people.index_by(&:record_id)
      end

      def edit
        @title = "Budget — #{@budget.name}"
        @people = store.people
        @forecasts = store.budget_forecasts(@budget.record_id)
      end

      def update
        store.update_budget!(@budget.record_id, budget_params)
        redirect_to edit_path, notice: "Budget saved."
      end

      # Appends a projected-spend update (amount + date + reason) to this budget,
      # which Airtable rolls up into its current forecast.
      def forecast
        amount = parse_decimal(params[:amount])
        date = parse_date(params[:date])
        if amount.nil? || date.nil?
          return redirect_to(edit_path, alert: "Enter a valid amount and date for the forecast.")
        end

        store.create_forecast!(budget_id: @budget.record_id, amount: amount, date: date,
                               reason: params[:reason].to_s)
        redirect_to edit_path, notice: "Forecast added."
      end

      private

      def set_budget
        @budget = store.find_budget(params[:id])
        raise ActiveRecord::RecordNotFound if @budget.nil?
      end

      def edit_path
        edit_admin_reimbursements_budget_path(@budget.record_id)
      end

      # Operator-editable budget attributes. Rollups/formulas are never written.
      # +active+ (visible-to-submitters) and +owner_ids+ come from a checkbox and
      # a multi-select, so absence means "off" / "none". +initial_budget+ is only
      # sent when a valid number is given, so a blank field can't zero it.
      def budget_params
        attrs = {
          name: params[:name].to_s.strip,
          nominal_code: params[:nominal_code].to_s.strip,
          notes: params[:notes].to_s,
          budget_type: params[:budget_type].presence || @budget.budget_type,
          active: params[:active].present?,
          owner_ids: Array(params[:owner_ids]).reject(&:blank?)
        }
        initial = parse_decimal(params[:initial_budget])
        attrs[:initial_budget] = initial unless initial.nil?
        attrs
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
