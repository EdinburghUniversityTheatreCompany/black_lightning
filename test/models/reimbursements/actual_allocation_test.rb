require "test_helper"

module Reimbursements
  class ActualAllocationTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # Budget#credit_actual_total adds allocations to rows attached whole, so the sets must be
    # disjoint or a row counts twice. apportion_actual! keeps them apart; MySQL cannot check it.
    test "an allocation refuses an actual still attached to a budget whole" do
      budget = create_reimbursements_budget(name: "Fundraising", budget_type: "Income")
      attached = create_reimbursements_eusa_actual(credit: 100, budget: budget)

      allocation = ActualAllocation.new(eusa_actual: attached, budget: budget, amount: 100)

      assert_not allocation.valid?
      assert allocation.errors[:eusa_actual].present?
    end
  end
end
