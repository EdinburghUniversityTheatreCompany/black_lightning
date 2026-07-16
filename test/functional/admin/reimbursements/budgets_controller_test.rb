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

        @props = airtable_budget_record(id: "recBud1", name: "Props", nominal_code: "4000",
                                        active: true, initial_budget: 1000.0, remaining: 250.5,
                                        current_forecast: 800.0, committed_amount: 300.0,
                                        total_paid: 150.0, variance: -50.0, owner_ids: [ "recPer1" ])
        @income = airtable_budget_record(id: "recBud2", name: "Ticket income", budget_type: "Income")
        @alice = airtable_person_record(id: "recPer1", name: "Alice Owner", email: "alice@example.com")
        @bob = airtable_person_record(id: "recPer2", name: "Bob Owner", email: "bob@example.com")
        @forecast = airtable_budget_forecast_record(id: "recFc1", budget_id: "recBud1",
                                                    amount: 800.0, date: "2026-05-01",
                                                    reason: "Initial projection")

        rebuild_store
      end

      teardown do
        BaseController.store_builder = -> { ::Reimbursements::Store.new }
      end

      def rebuild_store
        @store, @client = build_fake_store(
          budgets: [ @props, @income ], people: [ @alice, @bob ],
          budget_forecasts: [ @forecast ]
        )
        BaseController.store_builder = -> { @store }
      end

      # --- Auth gating -------------------------------------------------------

      test "requires sign-in" do
        get :index
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        sign_in users(:committee)
        get :edit, params: { id: "recBud1" }
        assert_response :forbidden
      end

      test "the producer portal permission alone does not grant finance access" do
        producer = Role.create!(name: "Producer")
        producer.permissions << Permission.create(action: "access", subject_class: "reimbursements")
        submitter = users(:member_with_phone_number)
        submitter.add_role("Producer")
        sign_in submitter

        get :edit, params: { id: "recBud1" }

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
        # Current forecast, committed, total paid, remaining and variance surface.
        assert_includes response.body, "800"
        assert_includes response.body, "300"
        assert_includes response.body, "150"
        assert_includes response.body, "250"
      end

      test "flags a budget that has no owner" do
        sign_in @user
        ownerless = airtable_budget_record(id: "recBud3", name: "Unowned category")
        @store, @client = build_fake_store(budgets: [ ownerless ], people: [ @alice ])
        BaseController.store_builder = -> { @store }

        get :index

        assert_response :success
        assert_includes response.body, "No owner"
      end

      test "does not flag a budget that has an owner" do
        sign_in @user
        @store, @client = build_fake_store(budgets: [ @props ], people: [ @alice ])
        BaseController.store_builder = -> { @store }

        get :index

        assert_response :success
        assert_includes response.body, "Alice Owner"
        assert_not_includes response.body, "No owner"
      end

      # --- Budget health -----------------------------------------------------

      test "surfaces health figures and an over-budget flag for an over-budget budget" do
        sign_in @user
        overspent = airtable_budget_record(id: "recBud4", name: "Overspent set",
                                           initial_budget: 1000.0, remaining: -250.0,
                                           current_forecast: 1300.0, committed_amount: 1200.0,
                                           total_paid: 1250.0, variance: -300.0,
                                           owner_ids: [ "recPer1" ])
        @store, @client = build_fake_store(budgets: [ overspent ], people: [ @alice ])
        BaseController.store_builder = -> { @store }

        get :index

        assert_response :success
        # Over-budget indicator surfaces.
        assert_includes response.body, "Over budget"
        # The health figures (initial, committed, total paid, remaining) all render.
        assert_includes response.body, "1,000"
        assert_includes response.body, "1,200"
        assert_includes response.body, "1,250"
        assert_includes response.body, "250"
      end

      test "does not flag an in-budget budget as over budget" do
        sign_in @user
        @store, @client = build_fake_store(budgets: [ @props ], people: [ @alice ])
        BaseController.store_builder = -> { @store }

        get :index

        assert_response :success
        assert_not_includes response.body, "Over budget"
      end

      # --- Edit --------------------------------------------------------------

      test "edit shows the owner multi-select and forecast history" do
        sign_in @user
        get :edit, params: { id: "recBud1" }

        assert_response :success
        assert_equal "recBud1", assigns(:budget).record_id
        assert_equal %w[recPer1 recPer2], assigns(:people).map(&:record_id).sort
        assert_equal [ "recFc1" ], assigns(:forecasts).map(&:record_id)
        assert_includes response.body, "Alice Owner"
        assert_includes response.body, "Bob Owner"
        assert_includes response.body, "Initial projection"
      end

      test "editing an unknown budget 404s" do
        sign_in @user
        get :edit, params: { id: "recNope" }
        assert_response :not_found
      end

      # --- Update ------------------------------------------------------------

      test "a blank name is rejected, not written straight through to Airtable" do
        sign_in @user

        patch :update, params: { id: "recBud1", name: "  ", nominal_code: "4000",
                                 budget_type: "Expense" }

        assert_redirected_to edit_admin_reimbursements_budget_path("recBud1")
        assert_match(/Enter a budget name/, flash[:alert])
        assert_empty @client.updated
      end

      test "a blank nominal code is rejected" do
        sign_in @user

        patch :update, params: { id: "recBud1", name: "Props", nominal_code: " ",
                                 budget_type: "Expense" }

        assert_redirected_to edit_admin_reimbursements_budget_path("recBud1")
        assert_match(/Enter a nominal code/, flash[:alert])
        assert_empty @client.updated
      end

      test "a budget_type outside the allowed list is rejected" do
        sign_in @user

        patch :update, params: { id: "recBud1", name: "Props", nominal_code: "4000",
                                 budget_type: "Something else entirely" }

        assert_redirected_to edit_admin_reimbursements_budget_path("recBud1")
        assert_match(/Choose a valid budget type/, flash[:alert])
        assert_empty @client.updated
      end

      test "an owner_id that doesn't resolve to a real person is rejected" do
        sign_in @user

        patch :update, params: { id: "recBud1", name: "Props", nominal_code: "4000",
                                 budget_type: "Expense", owner_ids: [ "recPer1", "recPerGone" ] }

        assert_redirected_to edit_admin_reimbursements_budget_path("recBud1")
        assert_match(/owners no longer exist/i, flash[:alert])
        assert_empty @client.updated
      end

      test "update persists edited fields including owners" do
        sign_in @user

        patch :update, params: { id: "recBud1", name: "Set & construction", nominal_code: "4200",
                                 notes: "Split with lighting", initial_budget: "1875.5",
                                 budget_type: "Expense", active: "1",
                                 owner_ids: [ "recPer1", "recPer2" ] }

        assert_redirected_to edit_admin_reimbursements_budget_path("recBud1")
        budgets_field = FIELD_IDS[:budgets]
        table, record_id, fields = @client.updated.sole
        assert_equal :budgets, table
        assert_equal "recBud1", record_id
        assert_equal "Set & construction", fields[budgets_field[:name]]
        assert_equal "4200", fields[budgets_field[:nominal_code]]
        assert_equal "Split with lighting", fields[budgets_field[:notes]]
        assert_in_delta 1875.5, fields[budgets_field[:initial_budget]]
        assert_equal [ "recPer1", "recPer2" ], fields[budgets_field[:owner]]
        assert fields[budgets_field[:active]]
      end

      test "unchecking visible-to-submitters writes active false" do
        sign_in @user

        patch :update, params: { id: "recBud1", name: "Props", nominal_code: "4000",
                                 budget_type: "Expense" }

        _t, _r, fields = @client.updated.sole
        assert_not fields[FIELD_IDS[:budgets][:active]]
      end

      test "clearing all owners writes an empty link list" do
        sign_in @user

        patch :update, params: { id: "recBud1", name: "Props", nominal_code: "4000",
                                 budget_type: "Expense", active: "1" }

        _t, _r, fields = @client.updated.sole
        assert_equal [], fields[FIELD_IDS[:budgets][:owner]]
      end

      # --- Forecast create ---------------------------------------------------

      test "adding a forecast creates a linked Budget Forecasts record" do
        sign_in @user

        post :forecast, params: { id: "recBud1", amount: "750.50", date: "2026-06-01",
                                  reason: "Revised up" }

        assert_redirected_to edit_admin_reimbursements_budget_path("recBud1")
        table, fields = @client.created.sole
        assert_equal :budget_forecasts, table
        assert_equal [ "recBud1" ], fields[FIELD_IDS[:budget_forecasts][:budget]]
        assert_in_delta 750.5, fields[FIELD_IDS[:budget_forecasts][:amount]]
        assert_equal "2026-06-01", fields[FIELD_IDS[:budget_forecasts][:date]]
        assert_equal "Revised up", fields[FIELD_IDS[:budget_forecasts][:reason]]
      end

      test "a forecast with a missing amount or date is rejected without a write" do
        sign_in @user

        post :forecast, params: { id: "recBud1", amount: "", date: "2026-06-01" }

        assert_redirected_to edit_admin_reimbursements_budget_path("recBud1")
        assert_match(/valid amount and date/i, flash[:alert])
        assert_empty @client.created
      end
    end
  end
end
