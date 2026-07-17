require "test_helper"
require "bigdecimal"

module Reimbursements
  module Airtable
    class BudgetTest < ActiveSupport::TestCase
      def budget(**attrs)
        Budget.new(record_id: "recBud1", name: "Props", **attrs)
      end

      def bd(value) = BigDecimal(value.to_s)

      test "over_budget? is true only when remaining is negative" do
        assert budget(remaining: bd("-1")).over_budget?
        assert_not budget(remaining: bd("0")).over_budget?
        assert_not budget(remaining: bd("10")).over_budget?
        assert_not budget(remaining: nil).over_budget?, "nil means not loaded, not over"
      end

      test "over_budget? doesn't fire on committed/paid past initial when remaining is still positive" do
        # The exact contradiction the split fixes: forecast was raised, so the
        # money-left figure is positive even though committed passed the initial.
        b = budget(initial_budget: bd("100"), committed_amount: bd("150"), remaining: bd("20"))
        assert_not b.over_budget?, "positive remaining must not read as over budget"
        assert b.over_initial_budget?, "but it IS over the original figure"
      end

      test "over_initial_budget? never overlaps with over_budget?" do
        genuinely_over = budget(initial_budget: bd("100"), committed_amount: bd("150"), remaining: bd("-5"))
        assert genuinely_over.over_budget?
        assert_not genuinely_over.over_initial_budget?, "the two states are mutually exclusive"
      end

      test "over_initial_budget? fires on total_paid past initial too" do
        assert budget(initial_budget: bd("100"), total_paid: bd("120"), remaining: bd("5")).over_initial_budget?
      end

      test "an income budget is never over budget or over initial" do
        b = budget(budget_type: "Income", remaining: bd("-50"),
                   initial_budget: bd("100"), committed_amount: bd("200"))
        assert_not b.over_budget?
        assert_not b.over_initial_budget?
      end

      test "a healthy budget flags neither state" do
        b = budget(initial_budget: bd("100"), committed_amount: bd("40"),
                   total_paid: bd("30"), remaining: bd("60"))
        assert_not b.over_budget?
        assert_not b.over_initial_budget?
      end
    end
  end
end
