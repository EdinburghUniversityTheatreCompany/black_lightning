module Reimbursements
  ##
  # A budget category in the Airtable Budgets table.
  class Budget
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
  end
end
