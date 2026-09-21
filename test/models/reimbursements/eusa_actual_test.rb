require "test_helper"

module Reimbursements
  class EusaActualTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

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

    # --- apportionment -----------------------------------------------------

    test "a credit row with no links is apportionable" do
      assert_predicate create_reimbursements_eusa_actual(credit: 4000), :apportionable?
    end

    test "a debit row is not apportionable" do
      assert_not_predicate create_reimbursements_eusa_actual(debit: 4000), :apportionable?
    end

    test "an offsetting leg is never apportionable" do
      actual = create_reimbursements_eusa_actual(credit: 4000,
                                                 reconciliation_status: EusaActual::STATUS_OFFSET)

      assert_not_predicate actual, :apportionable?
    end

    test "a row already attached to a budget is not apportionable" do
      budget = create_reimbursements_budget(name: "Fundraising", budget_type: "Income")
      actual = create_reimbursements_eusa_actual(credit: 4000, budget: budget)

      assert_not_predicate actual, :apportionable?
    end

    test "a row already attached to an expense is not apportionable" do
      expense = Expense.create!(status: Status::PAID, description: "x")
      actual = create_reimbursements_eusa_actual(credit: 4000, expense: expense)

      assert_not_predicate actual, :apportionable?
    end

    test "an already apportioned row is not apportionable again" do
      budget = create_reimbursements_budget(name: "Fundraising", budget_type: "Income")
      actual = create_reimbursements_eusa_actual(credit: 4000)
      ActualAllocation.create!(eusa_actual: actual, budget: budget, amount: 4000)

      assert_predicate actual.reload, :apportioned?
      assert_not_predicate actual, :apportionable?
      assert_equal BigDecimal("4000"), actual.allocated_total
    end

    # The figure a split must add up to is derived exactly as EusaActual.net
    # derives every rollup's: credits less debits. NOT the stored `net`
    # column, which is parsed from the export's own Net cell and so is a
    # second statement of the same fact that can disagree with (or be blank
    # beside) the debit/credit pair the budget totals actually read.
    test "the apportionable total is credits less debits, not the stored net column" do
      actual = create_reimbursements_eusa_actual(credit: 4000, debit: 250)
      actual.update_column(:net, 0)

      assert_equal BigDecimal("3750"), actual.reload.apportionable_total
    end
  end
end
