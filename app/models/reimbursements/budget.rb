module Reimbursements
  ##
  # A budget category in the Airtable Budgets table.
  class Budget
    attr_reader :record_id, :name, :nominal_code, :active, :budget_type,
                :initial_budget, :remaining

    # +initial_budget+/+remaining+ (BigDecimal or nil) are operator-side fields:
    # the portal never needed them, but Review's over-budget check does. Nil
    # means "not loaded", which callers treat as "don't block".
    def initialize(record_id:, name:, nominal_code: "", active: true, budget_type: "Expense",
                   initial_budget: nil, remaining: nil)
      @record_id = record_id
      @name = name
      @nominal_code = nominal_code
      @active = active
      @budget_type = budget_type
      @initial_budget = initial_budget
      @remaining = remaining
    end

    def income?
      budget_type == "Income"
    end
  end
end
