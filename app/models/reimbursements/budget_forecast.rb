module Reimbursements
  ##
  # A versioned projected-expenditure update for a Budget, stored in the
  # Airtable Budget Forecasts table. Each row is one dated projection with a
  # reason; the Budgets table rolls the latest up into +current_forecast+. The
  # finance Budgets screen shows a budget's forecast history and lets the
  # operator append a new one.
  class BudgetForecast
    attr_reader :record_id, :budget_id, :amount, :date, :reason, :name

    # +amount+ is a BigDecimal (or nil); +date+ a Date (or nil). +name+ is an
    # Airtable formula label, read-only.
    def initialize(record_id:, budget_id: nil, amount: nil, date: nil, reason: "", name: "")
      @record_id = record_id
      @budget_id = budget_id
      @amount = amount
      @date = date
      @reason = reason
      @name = name
    end
  end
end
