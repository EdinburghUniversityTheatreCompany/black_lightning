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

      test "requires the finance permission" do
        sign_in users(:committee)
        get :index
        assert_response :forbidden
      end

      test "index lists logged budget updates newest first, each linking to its page" do
        sign_in @user
        logged_update(date: Date.new(2026, 5, 1), note: "May meeting",
                      forecasts: [ { budget_id: @props.record_id, amount: 100 } ])
        june = logged_update(date: Date.new(2026, 6, 1), note: "June meeting",
                             forecasts: [ { budget_id: @travel.record_id, amount: 200 } ])

        get :index

        assert_response :success
        assert_equal 2, assigns(:budget_updates).size
        assert_equal Date.new(2026, 6, 1), assigns(:budget_updates).first.effective_date
        assert_includes response.body, "June meeting"
        assert_includes response.body, "May meeting"
        assert_select "a[href=?]", admin_reimbursements_budget_update_path(june.record_id)
      end

      # An update groups both levels, so an area forecast (no budget_id) must be named too.
      test "index names an area total revision as well as a line's, qualified" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito")
        @props.update!(area: area)
        logged_update(date: Date.new(2026, 5, 1), note: "May meeting",
                      forecasts: [ { budget_id: @props.record_id, amount: 100 },
                                   { area_id: area.record_id, amount: 5000 } ])

        get :index

        assert_response :success
        revised = css_select("tbody td:nth-child(3)").sole.text.squish
        assert_equal "Cogito (area total), Cogito: Props", revised
      end

      test "new renders an amount field for each active budget, hidden budgets excluded" do
        sign_in @user
        get :new

        assert_response :success
        assert_select "input[name=?]", "amounts[#{@props.record_id}]"
        assert_select "input[name=?]", "amounts[#{@travel.record_id}]"
        assert_select "input[name=?]", "amounts[#{@hidden.record_id}]", false
      end

      test "create logs one forecast per filled-in budget and skips blanks" do
        sign_in @user

        assert_difference -> { ::Reimbursements::BudgetUpdate.count }, 1 do
          assert_difference -> { ::Reimbursements::BudgetForecast.count }, 2 do
            post :create, params: {
              effective_date: "2026-06-01", note: "June meeting",
              amounts: { @props.record_id => "1,200", @travel.record_id => "£250",
                         @hidden.record_id => "" }
            }
          end
        end

        assert_redirected_to admin_reimbursements_budget_updates_path
        update = ::Reimbursements::BudgetUpdate.order(:id).last
        assert_equal Date.new(2026, 6, 1), update.effective_date
        assert_equal "June meeting", update.note
        assert_equal @user.id, update.created_by_id
        assert_equal BigDecimal("1200"), ::Reimbursements::Budget.find(@props.id).current_forecast
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

      test "create with a malformed effective date keeps the typed amounts and note" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::BudgetUpdate.count } do
          post :create, params: { effective_date: "not-a-date", note: "June meeting",
                                  amounts: { @props.record_id => "500",
                                             @travel.record_id => "250" } }
        end

        # Re-rendered, not redirected, so the typed numbers survive.
        assert_response :unprocessable_entity
        assert_match(/valid effective date/i, response.body)
        assert_select "input[name=?][value=?]", "amounts[#{@props.record_id}]", "500"
        assert_select "input[name=?][value=?]", "amounts[#{@travel.record_id}]", "250"
        assert_select "input[name=note][value=?]", "June meeting"
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
        # The whole update fails: the good budget's forecast is not logged either.
        assert_nil ::Reimbursements::Budget.find(@props.id).current_forecast
        assert_match(/Check the amount for .*Travel/, response.body)
        assert_includes response.body, "twelve pounds"
        assert_select "input[name=?][value=?]", "amounts[#{@props.record_id}]", "500"
      end

      # The summary must name the show, or it points at identically-named rows all at once.
      test "the error summary names the show, so it says which ROW to look at" do
        sign_in @user
        cogito = create_reimbursements_area(name: "Cogito")
        last_orders = create_reimbursements_area(name: "Last Orders")
        mine = create_reimbursements_budget(name: "Marketing", nominal_code: "432320", area: cogito)
        theirs = create_reimbursements_budget(name: "Marketing", nominal_code: "432320",
                                              area: last_orders)

        post :create, params: {
          effective_date: "2026-06-01", note: "one good one bad",
          amounts: { mine.record_id => "twelve pounds", theirs.record_id => "250" }
        }

        assert_response :unprocessable_entity
        # Assert off the flash, not the body: the alert reaches the page as JSON for SweetAlert.
        assert_equal "Nothing was saved. Check the amount for Cogito: Marketing.",
                     Array(flash[:error]).sole
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

      test "the page states each line's new amount and what it replaced" do
        ::Reimbursements::DatabaseStore.new.create_forecast!(
          budget_id: @props.record_id, amount: 100, date: Date.new(2026, 5, 1), reason: "May meeting"
        )
        update = logged_update
        sign_in @user

        get :show, params: { id: update.record_id }

        row = assigns(:rows).sole
        assert_equal BigDecimal("100"), row[:replaced]
        assert_equal BigDecimal("250"), row[:amount]
        assert_response :success
        assert_includes response.body, "£250.00"
        assert_match(/Props/, response.body)
      end

      # A first forecast replaced the committee's initial figure, which is what removal falls back to.
      test "a line's first forecast reports the initial budget as what it replaced" do
        @props.update!(initial_budget: 400)
        update = logged_update
        sign_in @user

        get :show, params: { id: update.record_id }

        row = assigns(:rows).sole
        assert_nil row[:replaced]
        assert_equal BigDecimal("400"), row[:initial]
      end

      test "removing an update puts each line back on the forecast it had before" do
        ::Reimbursements::DatabaseStore.new.create_forecast!(
          budget_id: @props.record_id, amount: 100, date: Date.new(2026, 5, 1), reason: "May meeting"
        )
        update = logged_update
        sign_in @user
        # Re-found, never reloaded: Budget#current_forecast memoizes into an ivar that reload
        # does not clear.
        assert_equal BigDecimal("250"), ::Reimbursements::Budget.find(@props.id).current_forecast

        delete :destroy, params: { id: update.record_id }

        # Destroyed, not nullified: nullify would leave the 250 in place.
        assert_equal BigDecimal("100"), ::Reimbursements::Budget.find(@props.id).current_forecast
        refute ::Reimbursements::BudgetUpdate.exists?(update.id)
      end

      # A later revision already won, so removing this one moves no figure; the page must say so.
      test "a superseded revision is marked as such" do
        update = logged_update
        ::Reimbursements::DatabaseStore.new.create_forecast!(
          budget_id: @props.record_id, amount: 900, date: Date.new(2026, 7, 1), reason: "July meeting"
        )
        sign_in @user

        get :show, params: { id: update.record_id }

        assert assigns(:rows).sole[:superseded]
        assert_match(/superseded this one/, response.body)
      end

      test "an area's agreed total is named and marked as one" do
        area = create_reimbursements_area(name: "Cogito")
        update = logged_update(forecasts: [ { area_id: area.record_id, amount: 3000 } ])
        sign_in @user

        get :show, params: { id: update.record_id }

        assert_response :success
        assert_match(/Cogito \(area total\)/, response.body)
      end

      test "an unknown update is a 404, not a 500" do
        sign_in @user

        get :show, params: { id: "999999" }

        assert_response :not_found
      end

      private

      def logged_update(date: Date.new(2026, 6, 1), note: "June meeting", forecasts: nil)
        ::Reimbursements::DatabaseStore.new.create_budget_update!(
          effective_date: date, note: note, created_by: @user,
          forecasts: forecasts || [ { budget_id: @props.record_id, amount: 250 } ]
        )
      end
    end
  end
end
