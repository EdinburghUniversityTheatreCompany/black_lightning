module Admin
  module Reimbursements
    # The four states the headline figures have to survive, taken from the shapes
    # production actually holds (see plans/area-pages-design.md).
    class SpendFiguresComponentPreview < ViewComponent::Preview
      # A show with an agreed total and room left.
      def default
        render SpendFiguresComponent.new(summary: summary(4_600, 1_236, 120), finance: false)
      end

      # What finance sees: the same figures, each with the portal's own name for it.
      def as_finance
        render SpendFiguresComponent.new(summary: summary(4_600, 1_236, 120), finance: true)
      end

      # No agreed total, so the comparator is what the lines add up to and says so.
      def total_taken_from_its_lines
        render SpendFiguresComponent.new(
          summary: summary(2_700, 2_301, 0, from_lines: true), finance: false
        )
      end

      # Genuinely over: "£2,426.13 over" rather than a bare negative.
      def over_budget
        render SpendFiguresComponent.new(summary: summary(100, 2_526.13, 0), finance: false)
      end

      # The commonest termtime shape — a £0 agreed total with real spend against
      # it, which reads as nobody having set one rather than as an overspend.
      def no_budget_set
        render SpendFiguresComponent.new(summary: summary(nil, 3_273.20, 0), finance: false)
      end

      private

      def summary(budget, spent, waiting, from_lines: false)
        ::Reimbursements::SpendSummary.new(
          budget_amount: budget && BigDecimal(budget.to_s), spent: BigDecimal(spent.to_s),
          waiting: BigDecimal(waiting.to_s), from_lines: from_lines
        )
      end
    end
  end
end
