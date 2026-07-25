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

    # --- offset legs -------------------------------------------------------

    test "an unstamped row is neither an offset nor pointing at a counterpart" do
      actual = EusaActual.create!(nominal_code: "4000", narrative: "BACS RUN", debit: 10)

      assert_not_predicate actual, :offset?
      assert_nil actual.offset_of
    end

    test "offset legs point at each other" do
      accrual = EusaActual.create!(nominal_code: "4000", narrative: "ACCRUAL", debit: 10,
                                   reconciliation_status: EusaActual::STATUS_OFFSET)
      reversal = EusaActual.create!(nominal_code: "4000", narrative: "REVERSAL", credit: 10,
                                    reconciliation_status: EusaActual::STATUS_OFFSET,
                                    offset_of: accrual)
      accrual.update!(offset_of: reversal)

      assert_predicate accrual.reload, :offset?
      assert_predicate reversal.reload, :offset?
      assert_equal reversal, accrual.offset_of
      assert_equal accrual, reversal.offset_of
    end

    # An offset leg is bookkeeping noise that nets to zero, so it must never be
    # turned into an expense however it is linked.
    test "an offset leg is never convertible to an expense" do
      actual = EusaActual.create!(nominal_code: "4000", narrative: "ACCRUAL", debit: 10,
                                  reconciliation_status: EusaActual::STATUS_OFFSET)

      assert_not_predicate actual, :convertible_to_expense?
    end

    test "an unlinked debit row is convertible to an expense" do
      actual = EusaActual.create!(nominal_code: "4000", narrative: "EUSA STAFF COST", debit: 10)

      assert_predicate actual, :convertible_to_expense?
    end

    test "a credit row is not convertible to an expense" do
      actual = EusaActual.create!(nominal_code: "4000", narrative: "TICKET INCOME", credit: 10)

      assert_not_predicate actual, :convertible_to_expense?
    end

    test "a debit row already linked to an expense is not convertible again" do
      expense = Expense.create!(status: Status::PAID, description: "x")
      actual = EusaActual.create!(nominal_code: "4000", narrative: "EUSA STAFF COST", debit: 10,
                                  expense: expense)

      assert_not_predicate actual, :convertible_to_expense?
    end
  end
end
