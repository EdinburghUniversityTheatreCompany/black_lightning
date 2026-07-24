require "test_helper"

module Admin
  module Reimbursements
    class BudgetUpdatesControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)
        @props = create_reimbursements_budget(name: "Props", nominal_code: "4000", active: true)
        @travel = create_reimbursements_budget(name: "Travel", nominal_code: "4100", active: true)
        @hidden = create_reimbursements_budget(name: "Payroll", nominal_code: "7000", active: false)
      end

      # --- Auth gating -------------------------------------------------------

      test "requires the finance permission" do
        sign_in users(:committee)
        get :index
        assert_response :forbidden
      end

      # --- Index -------------------------------------------------------------

      test "index lists logged budget updates newest first" do
        sign_in @user
        store = ::Reimbursements::DatabaseStore.new
        store.create_budget_update!(effective_date: Date.new(2026, 5, 1), note: "May meeting",
                                    created_by: @user,
                                    forecasts: [ { budget_id: @props.record_id, amount: 100 } ])
        store.create_budget_update!(effective_date: Date.new(2026, 6, 1), note: "June meeting",
                                    created_by: @user,
                                    forecasts: [ { budget_id: @travel.record_id, amount: 200 } ])

        get :index

        assert_response :success
        assert_equal 2, assigns(:budget_updates).size
        # Newest (June) first.
        assert_equal Date.new(2026, 6, 1), assigns(:budget_updates).first.effective_date
        assert_includes response.body, "June meeting"
        assert_includes response.body, "May meeting"
      end

      # --- New ---------------------------------------------------------------

      test "new renders an amount field for each active budget, hidden budgets excluded" do
        sign_in @user
        get :new

        assert_response :success
        assert_select "input[name=?]", "amounts[#{@props.record_id}]"
        assert_select "input[name=?]", "amounts[#{@travel.record_id}]"
        assert_select "input[name=?]", "amounts[#{@hidden.record_id}]", false
      end

      # --- Create ------------------------------------------------------------

      test "create logs one forecast per filled-in budget and skips blanks" do
        sign_in @user

        assert_difference -> { ::Reimbursements::BudgetUpdate.count }, 1 do
          assert_difference -> { ::Reimbursements::BudgetForecast.count }, 2 do
            post :create, params: {
              effective_date: "2026-06-01", note: "June meeting",
              amounts: { @props.record_id => "500", @travel.record_id => "250",
                         @hidden.record_id => "" }
            }
          end
        end

        assert_redirected_to admin_reimbursements_budget_updates_path
        update = ::Reimbursements::BudgetUpdate.order(:id).last
        assert_equal Date.new(2026, 6, 1), update.effective_date
        assert_equal "June meeting", update.note
        assert_equal @user.id, update.created_by_id
        assert_equal 2, update.forecasts.count
        # Each budget's current forecast is now the new amount.
        assert_equal BigDecimal("500"), ::Reimbursements::Budget.find(@props.id).current_forecast
        assert_equal BigDecimal("250"), ::Reimbursements::Budget.find(@travel.id).current_forecast
      end

      test "create with no amounts filled in is rejected without a write" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::BudgetUpdate.count } do
          post :create, params: { effective_date: "2026-06-01", note: "empty",
                                  amounts: { @props.record_id => "", @travel.record_id => "" } }
        end

        assert_redirected_to new_admin_reimbursements_budget_update_path
        assert_match(/at least one budget/i, flash[:alert])
      end

      test "create with a malformed effective date is rejected without a write" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::BudgetUpdate.count } do
          post :create, params: { effective_date: "not-a-date", note: "x",
                                  amounts: { @props.record_id => "500" } }
        end

        assert_redirected_to new_admin_reimbursements_budget_update_path
        assert_match(/valid effective date/i, flash[:alert])
      end

      test "a malformed amount is silently skipped, not written" do
        sign_in @user

        assert_difference -> { ::Reimbursements::BudgetForecast.count }, 1 do
          post :create, params: {
            effective_date: "2026-06-01", note: "one good one bad",
            amounts: { @props.record_id => "500", @travel.record_id => "not-a-number" }
          }
        end

        assert_redirected_to admin_reimbursements_budget_updates_path
      end
    end
  end
end
