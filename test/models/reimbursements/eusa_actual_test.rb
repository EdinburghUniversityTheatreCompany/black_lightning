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

    # An offset leg nets to zero, so it must never become an expense however it is linked.
    test "only an unlinked debit row that is not an offset leg is convertible to an expense" do
      expense = Expense.create!(status: Status::PAID, description: "x")

      { { debit: 10 } => true,
        { credit: 10 } => false,
        { debit: 10, reconciliation_status: EusaActual::STATUS_OFFSET } => false,
        { debit: 10, expense: expense } => false }.each do |attrs, expected|
        assert_equal expected, create_reimbursements_eusa_actual(**attrs).convertible_to_expense?,
                     attrs.inspect
      end
    end

    # --- apportionment -----------------------------------------------------

    test "only an unattached credit that is not an offset leg is apportionable" do
      budget = create_reimbursements_budget(name: "Fundraising", budget_type: "Income")
      expense = Expense.create!(status: Status::PAID, description: "x")

      { { credit: 4000 } => true,
        { debit: 4000 } => false,
        { credit: 4000, reconciliation_status: EusaActual::STATUS_OFFSET } => false,
        { credit: 4000, budget: budget } => false,
        { credit: 4000, expense: expense } => false }.each do |attrs, expected|
        assert_equal expected, create_reimbursements_eusa_actual(**attrs).apportionable?,
                     attrs.inspect
      end
    end

    test "an already apportioned row is not apportionable again" do
      budget = create_reimbursements_budget(name: "Fundraising", budget_type: "Income")
      actual = create_reimbursements_eusa_actual(credit: 4000)
      ActualAllocation.create!(eusa_actual: actual, budget: budget, amount: 4000)

      assert_predicate actual.reload, :apportioned?
      assert_not_predicate actual, :apportionable?
      assert_equal BigDecimal("4000"), actual.allocated_total
    end

    # Credits less debits, as EusaActual.net derives every rollup's; NOT the stored `net`, which can
    # disagree with or be blank beside the debit/credit pair.
    test "the apportionable total is credits less debits, not the stored net column" do
      actual = create_reimbursements_eusa_actual(credit: 4000, debit: 250)
      actual.update_column(:net, 0)

      assert_equal BigDecimal("3750"), actual.reload.apportionable_total
    end
  end
end
