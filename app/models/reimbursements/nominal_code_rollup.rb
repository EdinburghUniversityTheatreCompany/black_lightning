module Reimbursements
  ##
  # The overview's subtotal of one nominal code's budgets (a nil code for the
  # grand total). A code can hold both types, so totals come from #by_type.
  NominalCodeRollup = Struct.new(:code, :budgets, :budget_type) do
    include RollupTotals

    private

    def with_budgets(budgets, type) = self.class.new(code, budgets, type)
  end
end
