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

      # On top of the setup (forecast 800, committed 300 = Approved 150 + Paid
      # 150), give @props a Pending expense of 275 (pipeline) and a reconciled
      # EUSA debit of 161 against its Paid expense — so every Track G rollup on
      # the line has a distinct, recognisable figure.
      def seed_pipeline_and_eusa_debit
        create_reimbursements_expense(budget: @props, status: ::Reimbursements::Status::PENDING,
                                      amount_excl_vat: 275, amount: 330, receipt: false)
        paid = @props.expenses.find { |e| e.status == ::Reimbursements::Status::PAID }
        ::Reimbursements::EusaActual.create!(expense: paid, nominal_code: "4000",
                                            debit: BigDecimal("161.00"))
      end

      test "index shows the pipeline, EUSA-actual and expected-outturn columns" do
        sign_in @user
        @income.destroy!
        seed_pipeline_and_eusa_debit

        get :index

        assert_response :success
        assert_includes response.body, "Pipeline"
        assert_includes response.body, "Paid (portal)"
        assert_includes response.body, "EUSA actual"
        assert_includes response.body, "Expected outturn"
        # Pipeline £275, EUSA actual £161, expected outturn = max(800, 300, 150, 161) = 800.
        assert_includes response.body, "275"
        assert_includes response.body, "161"
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

      # --- CSV export --------------------------------------------------------

      test "index CSV export answers a text/csv download named for today" do
        sign_in @user

        get :index, format: :csv

        assert_csv_download("budgets")
      end

      test "index CSV export carries every rollup column the table shows" do
        sign_in @user
        seed_pipeline_and_eusa_debit

        get :index, format: :csv

        rows = CSV.parse(response.body)
        assert_equal [ "Budget", "Nominal code", "Type", "Visible", "Initial", "Current forecast",
                       "Projected", "Committed", "Pipeline", "Paid (portal)", "EUSA actual",
                       "Expected outturn", "Remaining", "Variance", "Owners" ], rows.first
        assert_equal 3, rows.size, "header + two budgets"

        props = rows.find { |r| r[0] == "Props" }
        assert_equal "4000", props[1]
        assert_equal %w[Expense Visible], props.values_at(2, 3)
        assert_equal "1000.0", props[4], "initial"
        assert_equal "800.0", props[5], "current forecast"
        assert_equal "800.0", props[6], "projected falls back to initial only without a forecast"
        assert_equal "300.0", props[7], "committed (Approved 150 + Paid 150)"
        assert_equal "275.0", props[8], "pipeline (the Pending expense)"
        assert_equal "150.0", props[9], "paid via the portal"
        assert_equal "161.0", props[10], "the reconciled EUSA debit"
        assert_equal "800.0", props[11], "expected outturn = max(800, 300, 150, 161)"
        assert_equal "500.0", props[12], "remaining = 800 - 300"
        assert_equal "-200.0", props[13], "variance = 800 - 1000, still a usable number"
        assert_equal "Alice Owner", props[14]
      end

      test "index CSV export marks a hidden income budget as such" do
        sign_in @user
        @income.update!(active: false)

        get :index, format: :csv

        income = CSV.parse(response.body).find { |r| r[0] == "Ticket income" }
        assert_equal %w[Income Hidden], income.values_at(2, 3)
      end

      test "index CSV export lists every budget, not just the first page" do
        seed_paged_budgets(60)
        sign_in @user

        get :index, format: :csv

        assert_equal 61, CSV.parse(response.body).size, "header + all 60 budgets"
      end

      test "index CSV export neutralises a formula-injected budget name" do
        sign_in @user
        create_reimbursements_budget(name: "=1+1", nominal_code: "4200")

        get :index, format: :csv

        rows = CSV.parse(response.body)
        assert_includes rows.map(&:first), "'=1+1"
      end

      test "index offers a Download CSV link" do
        sign_in @user

        get :index

        assert_includes response.body, "Download CSV"
        assert_includes response.body, "/admin/reimbursements/budgets?format=csv"
      end

      test "a forecast amount typed with a comma or a pound sign is read" do
        sign_in @user

        post :forecast, params: { id: @props.record_id, amount: "£1,200", date: "2026-06-01",
                                  reason: "typed the way people type" }

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        assert_equal BigDecimal("1200"),
                     ::Reimbursements::Budget.find(@props.id).current_forecast
      end

      # --- Overview (nominal-code rollup) ------------------------------------

      test "overview requires the finance permission" do
        sign_in users(:committee)
        get :overview
        assert_response :forbidden
      end

      test "overview groups budgets by nominal code with a per-code subtotal" do
        sign_in @user
        # @props is nominal 4000, initial 1000. Add a second 4000 budget and a
        # 4100 budget so there are two groups.
        create_reimbursements_budget(name: "Set", nominal_code: "4000", initial_budget: 500)
        create_reimbursements_budget(name: "Travel", nominal_code: "4100", initial_budget: 200)

        get :overview

        assert_response :success
        # Both nominal codes head their own group.
        assert_includes response.body, "4000"
        assert_includes response.body, "4100"
        # The 4000 group's initial subtotal is 1000 + 500 = 1500.
        assert_includes response.body, "1,500"
        # Grand total initial = 1000 + 500 + 200 = 1700 (Income budget has no initial).
        assert_includes response.body, "1,700"
        assert_includes response.body, "Grand total"
      end

      test "overview totals expense and income budgets separately, never as one figure" do
        sign_in @user
        # @props (Expense) already carries initial 1000, so expense initial is
        # 1000 + 9000 = 10,000 and income initial is 8000. The old single
        # grand total reported 18,000, which is neither total spend nor net.
        create_reimbursements_budget(name: "Lighting", nominal_code: "4200",
                                     initial_budget: 9000)
        create_reimbursements_budget(name: "Programme ads", nominal_code: "8100",
                                     budget_type: "Income", initial_budget: 8000)

        get :overview

        assert_response :success
        expense_total, income_total = assigns(:grand_total).by_type
        assert_equal BigDecimal("10000"), expense_total.initial
        assert_equal BigDecimal("8000"), income_total.initial
        assert_includes response.body, "Grand total (Expense budgets)"
        assert_includes response.body, "Grand total (Income budgets)"
        assert_includes response.body, "£10,000.00"
        assert_includes response.body, "£8,000.00"
        assert_not_includes response.body, "£18,000.00"
      end

      test "overview marks each row's budget type and leaves income outturn blank" do
        sign_in @user
        create_reimbursements_budget(name: "Programme ads", nominal_code: "8100",
                                     budget_type: "Income", initial_budget: 8000)

        get :overview

        assert_response :success
        # A Type cell per row, so an income line can't be read as spend.
        assert_select "table.table thead th", text: "Type"
        assert_select "table.table tbody td", text: "Income"
        assert_select "table.table tbody td", text: "Expense"
        assert_nil assigns(:rollups).flat_map(&:budgets)
                                    .find { |b| b.name == "Programme ads" }.expected_outturn
      end

      test "overview lists unattributed actuals, including spend on a budgeted code" do
        sign_in @user
        # 4000 IS budgeted (@props), but nothing links this row to an expense, so
        # no budget's figures count it. It used to fall through both the rollups
        # and the "unbudgeted" list and vanish from the page entirely.
        ::Reimbursements::EusaActual.create!(nominal_code: "4000", narrative: "Unlinked hire",
                                             debit: BigDecimal("1250.00"))
        ::Reimbursements::EusaActual.create!(nominal_code: "9999", narrative: "Mystery charge",
                                             debit: BigDecimal("42.00"))
        # Linked to one of @props's expenses, so @props already counts it.
        linked = ::Reimbursements::Expense.where(budget_id: @props.id).first
        ::Reimbursements::EusaActual.create!(nominal_code: "4000", narrative: "Reconciled row",
                                             debit: BigDecimal("10.00"), expense: linked)

        get :overview

        assert_response :success
        assert_includes response.body, "Actuals not attributed to any budget"
        assert_includes response.body, "Unlinked hire"
        assert_includes response.body, "£1,250.00"
        assert_includes response.body, "Mystery charge"
        # Total unattributed = 1250 + 42 = 1292; the linked row is not in the list.
        assert_includes response.body, "£1,292.00"
        assert_not_includes response.body, "Reconciled row"
      end

      test "overview does not report a correctly-offset accrual pair as unattributed" do
        sign_in @user
        store = ::Reimbursements::DatabaseStore.new
        accrual = store.create_actual!(nominal_code: "4000", narrative: "ACCRUAL 4200",
                                       debit: BigDecimal("4200"))
        reversal = store.create_actual!(nominal_code: "4000", narrative: "REVERSAL 4200",
                                        credit: BigDecimal("4200"))
        store.link_offsetting_pair!(accrual.record_id, reversal.record_id)

        get :overview

        assert_response :success
        assert_includes response.body, "Every EUSA actual is attributed to a budget."
        assert_not_includes response.body, "ACCRUAL 4200"
        assert_not_includes response.body, "£4,200.00"
      end

      test "overview shows a friendly note when every actual is attributed" do
        sign_in @user
        get :overview

        assert_response :success
        assert_includes response.body, "Actuals not attributed to any budget"
        assert_includes response.body, "Every EUSA actual is attributed to a budget."
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

      test "the forecast log flags a forecast that came from a budget update" do
        sign_in @user
        store = ::Reimbursements::DatabaseStore.new
        store.create_budget_update!(effective_date: Date.new(2026, 6, 15), note: "June meeting",
                                    created_by: @user,
                                    forecasts: [ { budget_id: @props.record_id, amount: 999 } ])

        get :edit, params: { id: @props.record_id }

        assert_response :success
        assert_includes response.body, "June meeting"
        assert_includes response.body, "part of a budget update"
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
