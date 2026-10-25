require "test_helper"

module Admin
  module Reimbursements
    class BudgetLinesComponentTest < ViewComponent::TestCase
      # Unpersisted, with the DB-computed readers pinned, as the component's preview builds them.
      def line(name, income: false)
        budget = ::Reimbursements::Budget.new(name: name, nominal_code: "432320", active: true,
                                              budget_type: income ? "Income" : "Expense",
                                              initial_budget: BigDecimal("800"))
        budget.define_singleton_method(:record_id) { name.parameterize }
        budget.define_singleton_method(:committed_amount) { BigDecimal("120") }
        budget.define_singleton_method(:pipeline_amount) { BigDecimal("0") }
        budget.define_singleton_method(:eusa_actual_amount) { BigDecimal("0") }
        budget.define_singleton_method(:current_forecast) { nil }
        budget
      end

      def headings
        page.all("table").map { |table| table.all("thead th").map { |th| th.text(:all).squish } }
      end

      # Income is never totalled with spend, so it gets its own table and its own columns.
      test "spend and income budgets each get their own table and columns" do
        render_inline(BudgetLinesComponent.new(lines: [ line("Set") ],
                                               income_lines: [ line("Ticket income", income: true) ],
                                               finance: false))

        assert_equal [ %w[Name Budget Spent Waiting Left], %w[Name Expected Received] ], headings
        assert_selector "table:first-of-type tbody td", text: "Set"
        assert_selector "tbody td", text: "Ticket income"
      end

      test "finance also sees each budget's nominal code and an Edit column" do
        render_inline(BudgetLinesComponent.new(lines: [ line("Set") ],
                                               income_lines: [ line("Ticket income", income: true) ],
                                               finance: true))

        assert_equal [ [ "Name", "Nominal code", "Budget", "Spent", "Waiting", "Left", "Actions" ],
                       [ "Name", "Nominal code", "Expected", "Received" ] ], headings
        assert_selector "tbody td", text: "432320", count: 2
        assert_link "Edit", href: "/admin/reimbursements/budgets/set/edit"
      end
    end
  end
end
