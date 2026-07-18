require "test_helper"
require "bigdecimal"

module Reimbursements
  module Airtable
    class BudgetForecastTest < ActiveSupport::TestCase
      test "carries forecast attributes with defaults" do
        forecast = BudgetForecast.new(record_id: "recFc1", budget_id: "recBud1",
          amount: BigDecimal("450.00"), date: Date.new(2026, 7, 9), reason: "Extra props")

        assert_equal "recFc1", forecast.record_id
        assert_equal "recBud1", forecast.budget_id
        assert_equal BigDecimal("450.00"), forecast.amount
        assert_equal Date.new(2026, 7, 9), forecast.date
        assert_equal "Extra props", forecast.reason
        assert_equal "", forecast.name
      end

      test "budget_id, amount and date default to nil, reason/name to blank" do
        forecast = BudgetForecast.new(record_id: "recFc1")

        assert_nil forecast.budget_id
        assert_nil forecast.amount
        assert_nil forecast.date
        assert_equal "", forecast.reason
        assert_equal "", forecast.name
      end
    end
  end
end
