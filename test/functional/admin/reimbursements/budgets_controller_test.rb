require "test_helper"

module Admin
  module Reimbursements
    class BudgetsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      setup do
        finance = Role.create!(name: "Business Manager")
        finance.permissions << Permission.create(action: "manage", subject_class: "reimbursements_finance")
        users(:member).add_role("Business Manager")
        @user = users(:member)

        @alice = create_reimbursements_person(name: "Alice Owner", email: "alice@example.com")
        @bob = create_reimbursements_person(name: "Bob Owner", email: "bob@example.com")
        @props = create_reimbursements_budget(name: "Props", nominal_code: "4000", active: true,
                                              initial_budget: 1000, owners: [ @alice ])
        @income = create_reimbursements_budget(name: "Ticket income", budget_type: "Income")
        @forecast = @props.forecasts.create!(amount: 800, date: Date.new(2026, 5, 1),
                                             reason: "Initial projection")
        # Committed 300 (Approved 150 excl-VAT + Paid 150), paid 150 —
        # remaining computes to 800 - 300 = 500.
        create_reimbursements_expense(budget: @props, status: ::Reimbursements::Status::APPROVED,
                                      amount_excl_vat: 150, amount: 180, receipt: false)
        create_reimbursements_expense(budget: @props, status: ::Reimbursements::Status::PAID,
                                      amount_excl_vat: 150, amount: 180, receipt: false)
      end

      # --- Auth gating -------------------------------------------------------

      test "requires sign-in" do
        get :index
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        sign_in users(:committee)
        get :edit, params: { id: @props.record_id }
        assert_response :forbidden
      end

      test "the producer portal permission alone does not grant finance access" do
        producer = Role.create!(name: "Producer")
        producer.permissions << Permission.create(action: "access", subject_class: "reimbursements")
        submitter = users(:member_with_phone_number)
        submitter.add_role("Producer")
        sign_in submitter

        get :edit, params: { id: @props.record_id }

        assert_response :forbidden
      end

      # --- Index -------------------------------------------------------------

      test "lists all budgets with their financials" do
        sign_in @user
        get :index

        assert_response :success
        assert_equal 2, assigns(:budgets).size
        assert_includes response.body, "Props"
        assert_includes response.body, "Ticket income"
        # Current forecast, committed, total paid and remaining surface
        # (computed: forecast 800, committed 300, paid 150, remaining 500).
        assert_includes response.body, "800"
        assert_includes response.body, "300"
        assert_includes response.body, "150"
        assert_includes response.body, "500"
      end

      # Alphabetically-named so page 1 (A-Z sorted, 50 per page) is deterministic.
      def seed_paged_budgets(count)
        ::Reimbursements::Expense.delete_all
        ::Reimbursements::BudgetForecast.delete_all
        ::Reimbursements::BudgetOwner.delete_all
        ::Reimbursements::Budget.delete_all
        (1..count).each { |n| create_reimbursements_budget(name: format("Budget %03d", n)) }
      end

      test "index pages the list at 50 per page" do
        seed_paged_budgets(60)
        sign_in @user

        get :index

        assert_equal 50, assigns(:budgets).size
        assert_includes response.body, "Budget 001"
        assert_not_includes response.body, "Budget 051"
      end

      test "index page 2 returns the remaining slice, not page 1's rows" do
        seed_paged_budgets(60)
        sign_in @user

        get :index, params: { page: 2 }

        assert_equal 10, assigns(:budgets).size
        assert_includes response.body, "Budget 051"
        assert_not_includes response.body, "Budget 001"
      end

      test "flags a budget that has no owner" do
        sign_in @user
        create_reimbursements_budget(name: "Unowned category")

        get :index

        assert_response :success
        assert_includes response.body, "No owner"
      end

      test "does not flag a budget that has an owner" do
        sign_in @user
        @income.destroy!

        get :index

        assert_response :success
        assert_includes response.body, "Alice Owner"
        assert_not_includes response.body, "No owner"
      end

      test "does not flag a hidden (overhead) budget for having no owner" do
        # Hidden overhead lines (payroll, NI, contracts) will never have a
        # producer owner, so the "No owner" warning is suppressed for them — it
        # would only drown the signal on the visible budgets that need chasing.
        sign_in @user
        @income.destroy!
        create_reimbursements_budget(name: "Payroll", active: false)

        get :index

        assert_response :success
        assert_not_includes response.body, "No owner"
      end

      # --- Budget health -----------------------------------------------------

      test "surfaces health figures and an over-budget flag for an over-budget budget" do
        sign_in @user
        # Committed 1400 (Paid 1250 + Approved 150) against a 1300 forecast:
        # remaining computes to -100.
        overspent = create_reimbursements_budget(name: "Overspent set", initial_budget: 1000,
                                                 owners: [ @alice ])
        overspent.forecasts.create!(amount: 1300, date: Date.new(2026, 5, 1), reason: "plan")
        create_reimbursements_expense(budget: overspent, status: ::Reimbursements::Status::PAID,
                                      amount_excl_vat: 1250, amount: 1500, receipt: false)
        create_reimbursements_expense(budget: overspent, status: ::Reimbursements::Status::APPROVED,
                                      amount_excl_vat: 150, amount: 180, receipt: false)

        get :index

        assert_response :success
        # Over-budget indicator surfaces.
        assert_includes response.body, "Over budget"
        # The health figures (initial, committed, total paid) all render.
        assert_includes response.body, "1,000"
        assert_includes response.body, "1,400"
        assert_includes response.body, "1,250"
      end

      test "does not flag an in-budget budget as over budget" do
        sign_in @user
        @income.destroy!

        get :index

        assert_response :success
        assert_not_includes response.body, "Over budget"
      end

      test "flags 'Over original budget' (not 'Over budget') when the forecast still covers the overspend" do
        sign_in @user
        # Committed past the initial figure, but a raised forecast leaves a
        # positive remaining — must NOT show the alarming red "Over budget".
        revised = create_reimbursements_budget(name: "Revised set", initial_budget: 1000,
                                               owners: [ @alice ])
        revised.forecasts.create!(amount: 1400, date: Date.new(2026, 5, 1), reason: "revised up")
        create_reimbursements_expense(budget: revised, status: ::Reimbursements::Status::APPROVED,
                                      amount_excl_vat: 1200, amount: 1440, receipt: false)

        get :index

        assert_response :success
        assert_includes response.body, "Over original budget"
        assert_not_includes response.body, ">Over budget<"
      end

      # --- Edit --------------------------------------------------------------

      test "edit shows the owner checkboxes and forecast history" do
        sign_in @user
        get :edit, params: { id: @props.record_id }

        assert_response :success
        assert_equal @props.record_id, assigns(:budget).record_id
        assert_equal [ @alice, @bob ].map(&:record_id).sort, assigns(:people).map(&:record_id).sort
        assert_equal [ @forecast.record_id ], assigns(:forecasts).map(&:record_id)
        assert_includes response.body, "Alice Owner"
        assert_includes response.body, "Bob Owner"
        assert_includes response.body, "Initial projection"
        # A checkbox per person instead of a Ctrl-click multi-select; the current
        # owner (Alice) is pre-ticked, the non-owner (Bob) is not.
        assert_select "fieldset legend", text: "Owners"
        assert_select "input[type=checkbox][name='owner_ids[]'][value=#{@alice.record_id}][checked]"
        assert_select "input[type=checkbox][name='owner_ids[]'][value=#{@bob.record_id}]"
        assert_select "input[type=checkbox][name='owner_ids[]'][value=#{@bob.record_id}][checked]", false
      end

      test "editing an unknown budget 404s" do
        sign_in @user
        get :edit, params: { id: "999999" }
        assert_response :not_found
      end

      # --- Update ------------------------------------------------------------

      test "a blank name is rejected, not written straight through" do
        sign_in @user

        patch :update, params: { id: @props.record_id, name: "  ", nominal_code: "4000",
                                 budget_type: "Expense" }

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        assert_match(/Enter a budget name/, flash[:alert])
        assert_equal "Props", @props.reload.name
      end

      test "a blank nominal code is rejected" do
        sign_in @user

        patch :update, params: { id: @props.record_id, name: "Props", nominal_code: " ",
                                 budget_type: "Expense" }

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        assert_match(/Enter a nominal code/, flash[:alert])
        assert_equal "4000", @props.reload.nominal_code
      end

      test "a budget_type outside the allowed list is rejected" do
        sign_in @user

        patch :update, params: { id: @props.record_id, name: "Props", nominal_code: "4000",
                                 budget_type: "Something else entirely" }

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        assert_match(/Choose a valid budget type/, flash[:alert])
        assert_equal "Expense", @props.reload.budget_type
      end

      test "an owner_id that doesn't resolve to a real person is rejected" do
        sign_in @user

        patch :update, params: { id: @props.record_id, name: "Props", nominal_code: "4000",
                                 budget_type: "Expense",
                                 owner_ids: [ @alice.record_id, "999999" ] }

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        assert_match(/owners no longer exist/i, flash[:alert])
        assert_equal [ @alice.record_id ], @props.reload.owner_ids
      end

      test "update persists edited fields including owners" do
        sign_in @user

        patch :update, params: { id: @props.record_id, name: "Set & construction",
                                 nominal_code: "4200", notes: "Split with lighting",
                                 initial_budget: "1875.5", budget_type: "Expense", active: "1",
                                 owner_ids: [ @alice.record_id, @bob.record_id ] }

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        @props.reload
        assert_equal "Set & construction", @props.name
        assert_equal "4200", @props.nominal_code
        assert_equal "Split with lighting", @props.notes
        assert_in_delta 1875.5, @props.initial_budget
        assert_equal [ @alice, @bob ].map(&:record_id).sort, @props.owner_ids.sort
        assert @props.active
      end

      test "unchecking visible-to-submitters writes active false" do
        sign_in @user

        patch :update, params: { id: @props.record_id, name: "Props", nominal_code: "4000",
                                 budget_type: "Expense" }

        assert_not @props.reload.active
      end

      test "clearing all owners writes an empty link list" do
        sign_in @user

        patch :update, params: { id: @props.record_id, name: "Props", nominal_code: "4000",
                                 budget_type: "Expense", active: "1" }

        assert_empty @props.reload.owner_ids
      end

      # --- Forecast create ---------------------------------------------------

      test "adding a forecast creates a linked Budget Forecasts record" do
        sign_in @user

        assert_difference -> { @props.forecasts.count }, 1 do
          post :forecast, params: { id: @props.record_id, amount: "750.50", date: "2026-06-01",
                                    reason: "Revised up" }
        end

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        created = @props.forecasts.order(:id).last
        assert_in_delta 750.5, created.amount
        assert_equal Date.new(2026, 6, 1), created.date
        assert_equal "Revised up", created.reason
      end

      test "a forecast with a missing amount or date is rejected without a write" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::BudgetForecast.count } do
          post :forecast, params: { id: @props.record_id, amount: "", date: "2026-06-01" }
        end

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        assert_match(/valid amount and date/i, flash[:alert])
      end

      test "a forecast with a malformed (non-blank) amount is rejected without a write" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::BudgetForecast.count } do
          post :forecast, params: { id: @props.record_id, amount: "not-a-number", date: "2026-06-01" }
        end

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        assert_match(/valid amount and date/i, flash[:alert])
      end

      test "a forecast with a malformed (non-blank) date is rejected without a write" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::BudgetForecast.count } do
          post :forecast, params: { id: @props.record_id, amount: "750.50", date: "not-a-date" }
        end

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        assert_match(/valid amount and date/i, flash[:alert])
      end

      # --- Edit / delete a logged forecast -----------------------------------

      test "edit with ?edit_forecast renders that row as an inline edit form" do
        sign_in @user

        get :edit, params: { id: @props.record_id, edit_forecast: @forecast.record_id }

        assert_response :success
        assert_equal @forecast.record_id, assigns(:editing_forecast_id)
        assert_select "input[name=forecast_id][value=#{@forecast.record_id}]"
        assert_select "input[name=amount][value=?]", "800.0"
      end

      test "updating a forecast writes the corrected values" do
        sign_in @user

        patch :update_forecast, params: { id: @props.record_id, forecast_id: @forecast.record_id,
                                          amount: "912.34", date: "2026-06-02", reason: "Corrected" }

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        assert_match(/updated/i, flash[:notice])
        @forecast.reload
        assert_in_delta 912.34, @forecast.amount
        assert_equal Date.new(2026, 6, 2), @forecast.date
        assert_equal "Corrected", @forecast.reason
      end

      test "updating a forecast with a bad amount is rejected without a write" do
        sign_in @user

        patch :update_forecast, params: { id: @props.record_id, forecast_id: @forecast.record_id,
                                          amount: "nope", date: "2026-06-02" }

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        assert_match(/valid amount and date/i, flash[:alert])
        assert_in_delta 800, @forecast.reload.amount
      end

      test "deleting a forecast removes the record" do
        sign_in @user

        assert_difference -> { ::Reimbursements::BudgetForecast.count }, -1 do
          delete :delete_forecast, params: { id: @props.record_id, forecast_id: @forecast.record_id }
        end

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        assert_match(/removed/i, flash[:notice])
      end

      test "a forecast belonging to another budget can't be edited through this budget's URL" do
        # @forecast is linked to @props, so editing it via @income must be refused.
        sign_in @user

        patch :update_forecast, params: { id: @income.record_id, forecast_id: @forecast.record_id,
                                          amount: "999.00", date: "2026-06-02" }

        assert_redirected_to edit_admin_reimbursements_budget_path(@income.record_id)
        assert_match(/isn't part of this budget/i, flash[:alert])
        assert_in_delta 800, @forecast.reload.amount
      end

      test "deleting a forecast from another budget's URL is refused" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::BudgetForecast.count } do
          delete :delete_forecast, params: { id: @income.record_id, forecast_id: @forecast.record_id }
        end

        assert_redirected_to edit_admin_reimbursements_budget_path(@income.record_id)
        assert_match(/isn't part of this budget/i, flash[:alert])
      end
    end
  end
end
