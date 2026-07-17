require "test_helper"

module Reimbursements
  class EusaActualTest < ActiveSupport::TestCase
    test "linked ids wrap the single FKs as record-id string arrays" do
      actual = EusaActual.create!(nominal_code: "4000", narrative: "BACS RUN", debit: 10)
      assert_empty actual.linked_expense_ids
      assert_empty actual.linked_budget_ids

      expense = Expense.create!(status: Status::PAID, description: "x")
      budget = Budget.create!(name: "Props")
      actual.update!(expense: expense, budget: budget)

      assert_equal [ expense.record_id ], actual.linked_expense_ids
      assert_equal [ budget.record_id ], actual.linked_budget_ids
    end

    test "dedup_key matches Reconciliation's row key" do
      actual = EusaActual.create!(nominal_code: "4000", narrative: "BACS RUN",
                                  debit: BigDecimal("12.34"), credit: nil)
      assert_equal Reconciliation.actuals_row_dedup_key("4000", "BACS RUN", BigDecimal("12.34"), nil),
                   actual.dedup_key
    end
  end
end
