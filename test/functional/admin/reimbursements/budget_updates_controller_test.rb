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

        assert_response :unprocessable_entity
        assert_match(/at least one budget/i, response.body)
      end

      test "create with a malformed effective date keeps the typed amounts" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::BudgetUpdate.count } do
          post :create, params: { effective_date: "not-a-date", note: "x",
                                  amounts: { @props.record_id => "500",
                                             @travel.record_id => "250" } }
        end

        # Re-rendered, not redirected: 40 amounts typed after a budget meeting
        # must not evaporate because of one bad date.
        assert_response :unprocessable_entity
        assert_match(/valid effective date/i, response.body)
        assert_select "input[name=?][value=?]", "amounts[#{@props.record_id}]", "500"
        assert_select "input[name=?][value=?]", "amounts[#{@travel.record_id}]", "250"
      end

      test "an unreadable amount fails the whole update and names the budget" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::BudgetForecast.count } do
          assert_no_difference -> { ::Reimbursements::BudgetUpdate.count } do
            post :create, params: {
              effective_date: "2026-06-01", note: "one good one bad",
              amounts: { @props.record_id => "500", @travel.record_id => "twelve pounds" }
            }
          end
        end

        assert_response :unprocessable_entity
        # The good budget's forecast is NOT logged: the whole update fails, so
        # the flash can never claim "1 forecast logged" while a budget silently
        # kept its superseded figure.
        assert_nil ::Reimbursements::Budget.find(@props.id).current_forecast
        assert_match(/Check the amount for .*Travel/, response.body)
        assert_includes response.body, "twelve pounds"
        assert_select "input[name=?][value=?]", "amounts[#{@props.record_id}]", "500"
      end

      test "comma and pound-sign amounts are read, not dropped" do
        sign_in @user

        assert_difference -> { ::Reimbursements::BudgetForecast.count }, 3 do
          post :create, params: {
            effective_date: "2026-06-01", note: "typed the way people type",
            amounts: { @props.record_id => "1,200", @travel.record_id => "£1200",
                       @hidden.record_id => "12,50" }
          }
        end

        assert_redirected_to admin_reimbursements_budget_updates_path
        assert_equal BigDecimal("1200"), ::Reimbursements::Budget.find(@props.id).current_forecast
        assert_equal BigDecimal("1200"), ::Reimbursements::Budget.find(@travel.id).current_forecast
        # "12,50" is a comma decimal (12.50), not 1250 — same reading as the
        # submitter-facing ExpenseForm.
        assert_equal BigDecimal("12.5"), ::Reimbursements::Budget.find(@hidden.id).current_forecast
      end

      test "a budget deleted while the form was open is refused, not a 500" do
        sign_in @user
        stale_id = @travel.record_id
        @travel.destroy!

        assert_no_difference -> { ::Reimbursements::BudgetUpdate.count } do
          post :create, params: {
            effective_date: "2026-06-01", note: "raced with a deletion",
            amounts: { @props.record_id => "500", stale_id => "250" }
          }
        end

        assert_response :unprocessable_entity
        assert_match(/no longer exists/i, response.body)
        assert_nil ::Reimbursements::Budget.find(@props.id).current_forecast
      end
    end
  end
end
