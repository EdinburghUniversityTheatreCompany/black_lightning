require "test_helper"

module Reimbursements
  class BudgetForecastTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    test "a forecast may belong to an area instead of a budget" do
      area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
      BudgetForecast.create!(area: area, amount: 800, date: Date.current)

      assert_equal 800, area.current_forecast
      assert_equal 800, area.projected_amount
    end

    test "an area with no forecast projects its initial budget" do
      area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
      assert_nil area.current_forecast
      assert_equal 1_000, area.projected_amount
    end

    test "a forecast belonging to both, or to neither, is refused" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Contingency")

      assert_not BudgetForecast.new(area: area, budget: budget, amount: 1).valid?
      assert_not BudgetForecast.new(amount: 1).valid?
    end
  end
end
