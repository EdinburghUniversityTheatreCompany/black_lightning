module Reimbursements
  ##
  # A subtotal presenter for the budget overview: one nominal code and the
  # budgets filed under it, exposing each overview metric as the sum of the
  # group's budgets. Reused for the grand-total footer by passing every budget
  # with a nil code.
  #
  # A group can hold both budget types (nothing stops two budgets of different
  # types sharing a nominal code), so every total the page shows comes from
  # RollupTotals#by_type rather than from this object directly.
  NominalCodeRollup = Struct.new(:code, :budgets, :budget_type) do
    include RollupTotals

    private

    def with_budgets(budgets, type) = self.class.new(code, budgets, type)
  end
end
