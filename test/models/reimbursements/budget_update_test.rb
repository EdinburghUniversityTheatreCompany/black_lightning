require "test_helper"

module Reimbursements
  # A budget update groups several budgets' forecasts under one shared
  # effective date, note and author.
  class BudgetUpdateTest < ActiveSupport::TestCase
    test "requires an effective date" do
      update = BudgetUpdate.new
      assert_not update.valid?
      assert update.errors[:effective_date].present?
    end

    test "has_many forecasts, nullified (not destroyed) when the update is removed" do
      budget = Budget.create!(name: "Props", nominal_code: "4000")
      update = BudgetUpdate.create!(effective_date: Date.new(2026, 6, 1), note: "Meeting")
      forecast = BudgetForecast.create!(budget: budget, amount: 100, date: Date.new(2026, 6, 1),
                                        budget_update: update)

      assert_equal [ forecast.id ], update.forecasts.map(&:id)

      update.destroy!
      # The forecast survives (it is the budget's real data); only the link clears.
      assert BudgetForecast.exists?(forecast.id)
      assert_nil forecast.reload.budget_update_id
    end

    test "created_by links to a User" do
      user = users(:member)
      update = BudgetUpdate.create!(effective_date: Date.new(2026, 6, 1), created_by: user)
      assert_equal user, update.created_by
    end
  end
end
