module Admin
  module Reimbursements
    # The lines table. Previews build unpersisted budgets and pin the DB-computed
    # readers per instance, the pattern the reimbursements unit tests use.
    class BudgetLinesComponentPreview < ViewComponent::Preview
      def default
        render BudgetLinesComponent.new(
          lines: [ line("Marketing", "432320", 1_100, 692.09), line("Retreat", "432980", 1_500, 1_512.35) ],
          income_lines: [], finance: false
        )
      end

      def as_finance
        render BudgetLinesComponent.new(
          lines: [ line("Marketing", "432320", 1_100, 692.09) ], income_lines: [], finance: true
        )
      end

      # A show that also sells tickets: income is listed apart, never added in.
      def with_income
        render BudgetLinesComponent.new(
          lines: [ line("Set", "439998", 1_500, 620) ],
          income_lines: [ line("Ticket income", "410000", 800, 0, income: true) ], finance: false
        )
      end

      # 38 of 96 production lines carry no figure at all.
      def line_with_no_budget
        render BudgetLinesComponent.new(
          lines: [ line("Tech", nil, nil, 2_526.13) ], income_lines: [], finance: false
        )
      end

      def no_lines_yet
        render BudgetLinesComponent.new(lines: [], income_lines: [], finance: false)
      end

      private

      def line(name, code, plan, spent, income: false)
        budget = ::Reimbursements::Budget.new(
          name: name, nominal_code: code, active: true,
          budget_type: income ? "Income" : "Expense",
          initial_budget: plan && BigDecimal(plan.to_s)
        )
        committed = BigDecimal(spent.to_s)
        budget.define_singleton_method(:record_id) { name.parameterize }
        budget.define_singleton_method(:committed_amount) { committed }
        budget.define_singleton_method(:pipeline_amount) { BigDecimal("0") }
        budget.define_singleton_method(:eusa_actual_amount) { BigDecimal("0") }
        budget.define_singleton_method(:current_forecast) { nil }
        budget
      end
    end
  end
end
