module Reimbursements
  ##
  # A budget category in the Airtable Budgets table.
  class Budget
    attr_reader :record_id, :name, :nominal_code, :active, :budget_type

    def initialize(record_id:, name:, nominal_code: "", active: true, budget_type: "Expense")
      @record_id = record_id
      @name = name
      @nominal_code = nominal_code
      @active = active
      @budget_type = budget_type
    end

    def income?
      budget_type == "Income"
    end
  end
end
