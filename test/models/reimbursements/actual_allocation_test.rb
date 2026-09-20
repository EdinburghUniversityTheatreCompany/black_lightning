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
  end
end
