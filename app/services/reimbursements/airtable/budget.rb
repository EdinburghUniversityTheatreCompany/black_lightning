module Reimbursements
  module Airtable
    ##
    # A budget category in the Airtable Budgets table.
    class Budget
      TYPES = %w[Expense Income].freeze

      attr_reader :record_id, :name, :nominal_code, :active, :budget_type,
                  :initial_budget, :remaining, :owner_ids, :notes,
                  :current_forecast, :committed_amount, :total_paid, :variance

      # +initial_budget+/+remaining+ (BigDecimal or nil) are operator-side fields:
      # the portal never needed them, but Review's over-budget check does. Nil
      # means "not loaded", which callers treat as "don't block".
      #
      # The financials +current_forecast+ (rolled-up projected spend),
      # +committed_amount+, +total_paid+ and +variance+ are read-only Airtable
      # rollups/formulas surfaced on the finance Budgets screen. +owner_ids+ is a
      # many-to-many link to People; +notes+ is free text — both editable.
      def initialize(record_id:, name:, nominal_code: "", active: true, budget_type: "Expense",
                     initial_budget: nil, remaining: nil, owner_ids: [], notes: "",
                     current_forecast: nil, committed_amount: nil, total_paid: nil, variance: nil)
        @record_id = record_id
        @name = name
        @nominal_code = nominal_code
        @active = active
        @budget_type = budget_type
        @initial_budget = initial_budget
        @remaining = remaining
        @owner_ids = owner_ids
        @notes = notes
        @current_forecast = current_forecast
        @committed_amount = committed_amount
        @total_paid = total_paid
        @variance = variance
      end

      def income?
        budget_type == "Income"
      end

      # Genuinely overspent: nothing left against the current forecast/plan.
      # `remaining` is the one figure that unambiguously means "over" (an
      # Airtable rollup that already folds in forecast, committed and paid), so
      # the badge keys off it alone — mixing in the initial-figure checks below
      # produced a red "Over budget" next to a positive Remaining. Nil means
      # "not loaded"; income budgets are never over budget.
      def over_budget?
        return false if income?

        !remaining.nil? && remaining.negative?
      end

      # A softer state: committed or paid has passed the ORIGINAL initial figure,
      # but the forecast was revised up to cover it so there's still remaining.
      # Worth flagging (the plan grew) but not the same alarm as over_budget?.
      def over_initial_budget?
        return false if income? || over_budget?
        return true if initial_budget && committed_amount && committed_amount > initial_budget
        return true if initial_budget && total_paid && total_paid > initial_budget

        false
      end
    end
  end
end
