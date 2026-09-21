require "test_helper"

module Reimbursements
  class ActualAllocationTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    test "requires a positive amount" do
      allocation = ActualAllocation.new(amount: 0)

      assert_not allocation.valid?
      assert allocation.errors[:amount].present?
    end

    test "a budget appears at most once per actual" do
      actual = create_reimbursements_eusa_actual(credit: 100)
      budget = create_reimbursements_budget(name: "Fundraising", budget_type: "Income")
      ActualAllocation.create!(eusa_actual: actual, budget: budget, amount: 40)
      duplicate = ActualAllocation.new(eusa_actual: actual, budget: budget, amount: 60)

      assert_not duplicate.valid?
    end
    # Budget#credit_actual_total ADDS allocations to the rows attached whole, so
    # the two sets have to be disjoint or a row is counted twice. That holds
    # because apportion_actual! clears budget_id — a writer's promise, not a
    # database one, and MySQL cannot check it across two tables. This is the
    # belt and braces under it.
    test "an allocation refuses an actual still attached to a budget whole" do
      budget = create_reimbursements_budget(name: "Fundraising", budget_type: "Income")
      attached = create_reimbursements_eusa_actual(credit: 100, budget: budget)

      allocation = ActualAllocation.new(eusa_actual: attached, budget: budget, amount: 100)

      assert_not allocation.valid?
      assert allocation.errors[:eusa_actual].present?
    end
  end
end
