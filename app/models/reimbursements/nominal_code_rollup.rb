module Reimbursements
  ##
  # A subtotal presenter for the budget overview: one nominal code and the
  # budgets filed under it, exposing each overview metric as the sum of the
  # group's budgets. A budget's nil figure (e.g. no projected amount) counts as
  # zero so a partly-planned group still totals cleanly. Reused for the
  # grand-total footer by passing every budget with a nil code.
  NominalCodeRollup = Struct.new(:code, :budgets) do
    def initial     = sum_of(&:initial_budget)
    def projected   = sum_of(&:projected_amount)
    def committed   = sum_of(&:committed_amount)
    def pipeline    = sum_of(&:pipeline_amount)
    def paid_portal = sum_of(&:paid_portal_amount)
    def eusa_actual = sum_of(&:eusa_actual_amount)
    def expected    = sum_of(&:expected_outturn)

    private

    def sum_of(&block)
      budgets.sum { |budget| block.call(budget) || 0 }
    end
  end
end
