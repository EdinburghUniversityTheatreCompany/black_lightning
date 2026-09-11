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

      # The Airtable backend is gone and every figure on this page is computed locally, so
      # the intro copy must not send a reader looking for a base that no longer exists.
      test "index copy does not reference the retired Airtable backend" do
        sign_in @user
        get :index

        assert_response :success
        assert_no_match(/airtable/i, response.body)
      end

      # On top of the setup (forecast 800, committed 300 = Approved 150 + Paid
      # 150), give @props a Pending expense of 275 (pipeline) and a reconciled
      # EUSA debit of 161 against its Paid expense — so every rollup on the line
      # has a distinct, recognisable figure.
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
                       "Expected outturn", "Remaining", "Variance", "Owners", "Cost centre" ], rows.first
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

      # --- Area grouping ------------------------------------------------------

      test "the index groups budgets under their area and lists the rest separately" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
        create_reimbursements_budget(name: "Cogito: Marketing", area: area, initial_budget: 400)
        create_reimbursements_budget(name: "Contingency", initial_budget: 1_000)

        get :index

        assert_response :success
        assert_select "[data-area='#{area.record_id}']" do
          assert_select "td", text: /Cogito: Marketing/
        end
        assert_select "[data-area='none']" do
          assert_select "td", text: /Contingency/
        end
      end

      test "an area with no agreed total renders no Remaining figure, not a misleading zero" do
        sign_in @user
        area = create_reimbursements_area(name: "No total yet")
        create_reimbursements_budget(name: "No total yet: Set", area: area)

        get :index

        assert_response :success
        assert_select "[data-area='#{area.record_id}']" do |elements|
          assert_no_match(/Remaining/, elements.first.text)
        end
      end

      # Same shape as #seed_paged_budgets below, but every budget belongs to
      # ONE area — the fixture for the page-boundary test that follows.
      # Alphabetically-named for the same reason: page 1 (50/page) is
      # deterministic, so "Budget 001".."Budget 050" land on it and
      # "Budget 051".."Budget 060" spill to page 2.
      def seed_paged_area_budgets(count, area:)
        ::Reimbursements::Expense.delete_all
        ::Reimbursements::BudgetForecast.delete_all
        ::Reimbursements::BudgetOwner.delete_all
        ::Reimbursements::Budget.delete_all
        (1..count).each { |n| create_reimbursements_budget(name: format("Budget %03d", n), area: area) }
      end

      # The subtotal in the area's header always covers EVERY line linked to
      # it (area.budgets, unscoped — the same total Area#committed_amount and
      # #allocated already sum over), not just the rows visible on this page.
      # With 60 lines under one area and a 50-per-page index, page 1 renders
      # only 50 of them under a subtotal that covers all 60 — this is the case
      # the note exists to disclose, with real pagination doing the hiding
      # rather than a stub.
      test "an area whose lines straddle the page boundary states how many are shown" do
        sign_in @user
        area = create_reimbursements_area(name: "Big Area")
        seed_paged_area_budgets(60, area: area)

        get :index

        assert_response :success
        assert_select "[data-area='#{area.record_id}']" do |elements|
          assert_match(/50 of 60 lines shown/, elements.first.text)
        end
      end

      # The common case: nothing states a line count when every one of the
      # area's lines fits on the page — a permanent "X of X lines shown" would
      # be noise on every ordinary area, and this is what stops a future edit
      # from dropping the `visible_count < total_count` guard unnoticed.
      test "an area whose lines all fit on the page states nothing" do
        sign_in @user
        area = create_reimbursements_area(name: "Small Area")
        create_reimbursements_budget(name: "Small Area: One", area: area)
        create_reimbursements_budget(name: "Small Area: Two", area: area)

        get :index

        assert_response :success
        assert_select "[data-area='#{area.record_id}']" do |elements|
          assert_no_match(/lines shown/, elements.first.text)
        end
      end

      # Builds +area_count+ areas with +budgets_per_area+ budgets each, every
      # budget carrying an expense (so Budget#committed_amount queries) and a
      # forecast (so Budget#projected_amount/Area#allocated queries) — a
      # single area with a single budget can't tell a preloaded read from an
      # N+1, since both cost one query either way.
      def seed_areas_with_budgets(area_count:, budgets_per_area:)
        ::Reimbursements::Expense.delete_all
        ::Reimbursements::BudgetForecast.delete_all
        ::Reimbursements::BudgetOwner.delete_all
        ::Reimbursements::Budget.delete_all
        ::Reimbursements::Area.delete_all

        area_count.times do |a|
          area = create_reimbursements_area(name: "Area #{a}", initial_budget: 1_000)
          budgets_per_area.times do |n|
            budget = create_reimbursements_budget(name: "Area #{a}: Line #{n}", area: area,
                                                  initial_budget: 100)
            budget.forecasts.create!(amount: 150, date: Date.new(2026, 5, 1), reason: "plan")
            create_reimbursements_expense(budget: budget, status: ::Reimbursements::Status::APPROVED,
                                          amount_excl_vat: 50, amount: 60, receipt: false)
          end
        end
      end

      # Quadrupling the row count (2 areas/4 budgets -> 4 areas/16 budgets)
      # must not multiply the query count: DatabaseStore#areas preloads each
      # area's owners and its budgets' expenses/forecasts in a handful of
      # fixed queries, however many rows there are.
      test "the index's query count does not grow with the number of areas or budgets" do
        sign_in @user

        seed_areas_with_budgets(area_count: 2, budgets_per_area: 2)
        small_queries = count_queries { get :index }

        seed_areas_with_budgets(area_count: 4, budgets_per_area: 4)
        large_queries = count_queries { get :index }

        assert_operator large_queries, :<=, small_queries + 5,
                        "expected roughly the same query count for 4 budgets (#{small_queries}) " \
                        "and 16 budgets (#{large_queries}) across 2x the areas"
      end

      # Negative control for the assertion above: reading Area#committed_amount
      # / #allocated off Areas loaded WITHOUT the preload (as a bare
      # `Area.all` would be, the mistake the brief warns against — reading
      # budget.area's own #budgets association, or store.areas without its
      # `budgets: %i[expenses forecasts]` include) costs a query per budget's
      # expenses plus a query per budget's forecasts. This proves the positive
      # assertion above isn't vacuously true — an unpreloaded read really does
      # scale with row count, and the preloaded one really doesn't.
      test "negative control: an unpreloaded area read DOES scale with the number of areas/budgets" do
        sign_in @user

        seed_areas_with_budgets(area_count: 2, budgets_per_area: 2)
        small_areas = ::Reimbursements::Area.all.to_a
        small_queries = count_queries { small_areas.each { |a| a.committed_amount; a.allocated } }

        seed_areas_with_budgets(area_count: 4, budgets_per_area: 4)
        large_areas = ::Reimbursements::Area.all.to_a
        large_queries = count_queries { large_areas.each { |a| a.committed_amount; a.allocated } }

        assert_operator small_queries, :>, 4,
                        "expected reading committed_amount/allocated off unpreloaded areas to cost " \
                        "a query per budget even at the smaller size (got #{small_queries})"
        assert_operator large_queries, :>, small_queries,
                        "expected the unpreloaded read to scale with the row count: " \
                        "#{small_queries} queries for 4 budgets vs #{large_queries} for 16"
      end

      # Schema-introspection queries (the first touch of a table in a test
      # run) are excluded, or whichever test happens to run first absorbs
      # them and the comparison between two sizes becomes noise instead of
      # signal — measured: without this exclusion the SAME scenario read
      # 45 queries first and 31 second, entirely from schema-cache warmup.
      def count_queries(&block)
        count = 0
        callback = lambda do |*, payload|
          next if payload[:name] == "SCHEMA"
          next if payload[:sql].match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

          count += 1
        end
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
        count
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
        # @props is nominal 4000, initial 1000. Add a second 4000 budget and TWO
        # 4100 budgets, with amounts chosen so every subtotal is a figure no
        # individual row carries — otherwise an assertion on "4000" or "200" is
        # satisfied by the budget row itself and pins no grouping at all.
        create_reimbursements_budget(name: "Set", nominal_code: "4000", initial_budget: 500)
        create_reimbursements_budget(name: "Travel", nominal_code: "4100", initial_budget: 200)
        create_reimbursements_budget(name: "Digs", nominal_code: "4100", initial_budget: 350)

        get :overview

        assert_response :success
        # Each nominal code heads its own group, and each group ends in a subtotal.
        assert_includes response.body, "Nominal code 4000"
        assert_includes response.body, "Nominal code 4100"
        assert_includes response.body, "Subtotal 4000"
        assert_includes response.body, "Subtotal 4100"
        # Subtotals: 4000 = 1000 + 500 = 1500; 4100 = 200 + 350 = 550. Neither
        # figure appears on any single budget row.
        assert_includes response.body, "1,500"
        assert_includes response.body, "550"
        # Grand total initial = 1000 + 500 + 200 + 350 = 2050 (Income has none).
        assert_includes response.body, "2,050"
        assert_includes response.body, "Grand total"
      end

      test "the overview's query count does not grow with the number of budgets or areas" do
        sign_in @user
        # One area holding one budget with an expense and a linked actual, so
        # every preload on the page has rows to load before the baseline is taken
        # (Rails skips a preload query for an association with nothing to load,
        # which would otherwise make the two renders different shapes rather than
        # different sizes).
        seed_budget_with_actual(0)
        overview_query_count # warm up anything cached per process
        baseline = overview_query_count

        9.times { |i| seed_budget_with_actual(i + 1) }

        # Every figure on the page comes off a preloaded association, so nine more
        # areas, budgets, expenses and ledger rows cost exactly what one did. The
        # area figures are the ones at risk: read off budget.area instead of
        # store.areas, each area's committed/allocated would query per line.
        assert_equal baseline, overview_query_count
      end

      test "overview totals expense and income budgets separately, never as one figure" do
        sign_in @user
        # @props (Expense) already carries initial 1000, so expense initial is
        # 1000 + 9000 = 10,000 and income initial is 8000. A single grand total
        # would read 18,000, which is neither total spend nor net.
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
        # no budget's figures count it. A code-based "unbudgeted" list would let
        # it fall through both the rollups and the list, off the page entirely.
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
        # The card title renders either way, so assert the empty-state SENTENCE,
        # which only appears when the list really is empty.
        assert_includes response.body, "Actuals not attributed to any budget"
        assert_includes response.body, "Every EUSA actual is attributed to a budget."
        assert_empty assigns(:unattributed_by_code)
      end

      test "overview does not show the empty-state note when there IS unattributed spend" do
        sign_in @user
        ::Reimbursements::EusaActual.create!(nominal_code: "9999", narrative: "Mystery charge",
                                             debit: BigDecimal("42.00"))

        get :overview

        assert_response :success
        assert_not_includes response.body, "Every EUSA actual is attributed to a budget."
      end

      # --- Overview (area rollup) --------------------------------------------

      test "overview groups the same budgets by area, with the area's agreed total" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito", initial_budget: 5000)
        create_reimbursements_budget(name: "Marketing", nominal_code: "4300", area: area,
                                     initial_budget: 400)
        create_reimbursements_budget(name: "Set", nominal_code: "4400", area: area,
                                     initial_budget: 350)

        get :overview

        assert_response :success
        assert_includes response.body, "Budgets by area"
        # The heading span exists only on an area row, so a budget called
        # "Cogito something" could not satisfy this the way a body match would.
        assert_select "th[scope=rowgroup] span.font-semibold", text: "Cogito"
        # 750 = 400 + 350, a figure no single row carries, so the assertion pins
        # the grouping rather than a budget line.
        assert_includes response.body, "Subtotal Cogito (Expense)"
        assert_includes response.body, "£750.00"
        # The committee's agreed figure and what is left to split out of it
        # (5000 - 750), both read off the area rather than off its lines.
        assert_includes response.body, "Agreed total £5,000.00"
        assert_includes response.body, "£4,250.00 not yet allocated"
        # Props and the income line belong to no area, and still have to appear —
        # under a heading, never behind an empty state.
        assert_includes response.body, "Not in an area"
        assert_not_includes response.body, "No budgets to group."
      end

      test "overview never totals an area's expense and income lines together" do
        sign_in @user
        # An agreed total, so the one figure that would net the two types
        # against each other is actually reached and can be asserted on.
        area = create_reimbursements_area(name: "Cogito", initial_budget: 1000)
        create_reimbursements_budget(name: "Cogito marketing", nominal_code: "4300", area: area,
                                     initial_budget: 410)
        create_reimbursements_budget(name: "Cogito tickets", nominal_code: "8100", area: area,
                                     budget_type: "Income", initial_budget: 805)

        get :overview

        assert_response :success
        rollup = assigns(:area_rollups).sole
        spend, income = rollup.by_type
        assert_equal BigDecimal("410"), spend.initial
        assert_equal BigDecimal("805"), income.initial
        assert_includes response.body, "Subtotal Cogito (Expense)"
        assert_includes response.body, "Subtotal Cogito (Income)"
        # 1,215 is neither the show's spend nor its income, so nothing says it.
        assert_not_includes response.body, "£1,215.00"
        # Area#unallocated is 1000 - 410 - 805 = -215, spend netted against
        # income and indistinguishable from real over-allocation. The agreed
        # total still stands: it is one figure the committee agreed, not a sum.
        assert_equal BigDecimal("-215"), rollup.area.unallocated
        assert_nil rollup.unallocated
        assert_includes response.body, "Agreed total £1,000.00"
        assert_not_includes response.body, "-£215.00"
        assert_not_includes response.body, "not yet allocated"
        assert_includes response.body,
                        "No allocation figure: this area holds both expense and income lines."
      end

      test "an area with no agreed total shows no figure, never a zero" do
        sign_in @user
        # The area and its line share no substring, so neither assertion below
        # can pass off the other's name.
        area = create_reimbursements_area(name: "Backfilled show")
        create_reimbursements_budget(name: "Props ledger", nominal_code: "4300", area: area,
                                     initial_budget: 400)

        get :overview

        assert_response :success
        assert_select "th[scope=rowgroup] span.font-semibold", text: "Backfilled show"
        # "Agreed total £0.00" would read as the show being fully overspent.
        assert_not_includes response.body, "Agreed total"
        assert_not_includes response.body, "not yet allocated"
      end

      test "an area holding a line outside the selected year says how many are shown" do
        this_year, next_year = seed_two_years
        sign_in @user
        area = create_reimbursements_area(name: "Cogito", financial_year: this_year,
                                          initial_budget: 5000)
        create_reimbursements_budget(name: "Cogito marketing", nominal_code: "4300", area: area,
                                     initial_budget: 400, financial_year: this_year)
        # Reachable by an ordinary edit, and the budget form preserves it
        # deliberately, so the overview has to state it rather than drop it.
        create_reimbursements_budget(name: "Cogito next year", nominal_code: "4300", area: area,
                                     initial_budget: 900, financial_year: next_year)

        get :overview, params: { year: this_year.key }

        assert_response :success
        # The totals cover the year on screen: the other line is not listed...
        assert_not_includes response.body, "Cogito next year"
        # ...while the area's own unallocated figure subtracts both lines
        # (5000 - 400 - 900), which is exactly the disagreement the row names.
        assert_includes response.body, "£3,700.00 not yet allocated"
        # Pinned whole: the sentence's only job is to stop a finance user
        # misreading two disagreeing figures, so every clause has to be true.
        # The agreed total is named by neither: it counts no lines at all.
        assert_equal "1 of 2 lines shown. 1 line in another year or cost centre, left out of " \
                     "the totals below but already subtracted from the not-yet-allocated figure.",
                     css_select("span.text-warning").sole.text.squish

        # With no agreed total there is no allocation figure on screen, so the
        # sentence must not claim one.
        area.update!(initial_budget: nil)
        get :overview, params: { year: this_year.key }

        assert_not_includes response.body, "not yet allocated"
        assert_equal "1 of 2 lines shown. 1 line in another year or cost centre, left out of " \
                     "the totals below.",
                     css_select("span.text-warning").sole.text.squish
      end

      test "the area card's empty state appears only when there is nothing to group" do
        sign_in @user
        # Budgets but no areas is not an empty page: they group under "Not in an
        # area", and a banner over a full table would contradict it.
        get :overview

        assert_includes response.body, "Not in an area"
        assert_not_includes response.body, "No budgets to group."

        ::Reimbursements::EusaActual.delete_all
        ::Reimbursements::Expense.destroy_all
        ::Reimbursements::Budget.destroy_all

        get :overview

        assert_response :success
        assert_includes response.body, "No budgets to group."
      end

      test "the area card reads its figures off store.areas, not off budget.area" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito", initial_budget: 5000)
        create_reimbursements_budget(name: "Marketing", nominal_code: "4300", area: area,
                                     initial_budget: 400)

        get :overview

        assert_response :success
        rollup = assigns(:area_rollups).sole
        # store.areas is the unscoped, fully-preloaded reader; the line count on
        # the heading comes off that loaded collection rather than a COUNT.
        assert rollup.area.budgets.loaded?
        assert_equal 1, rollup.lines_total
        assert_equal 0, rollup.lines_out_of_scope
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

      # The breadcrumb is built from the URL, so an unresolved id segment titleizes
      # into nonsense ("Budgets / 12 / Edit", or "Rec X Ko G9m U Fbu Dn5 A" on an
      # Airtable id); the segment resolves to the loaded record's name instead.
      test "the edit breadcrumb names the budget instead of its id" do
        sign_in @user

        get :edit, params: { id: @props.record_id }

        assert_response :success
        assert_select "nav[aria-label=Breadcrumb]" do |nav|
          assert_match(/Props/, nav.first.text)
          assert_no_match(/#{@props.record_id}/, nav.first.text)
        end
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

      test "a budget can be moved between areas from its own form" do
        sign_in @user

        from = create_reimbursements_area(name: "Cogito")
        to = create_reimbursements_area(name: "Improverts")
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: from)

        patch :update, params: { id: budget.record_id, name: budget.name,
                                 nominal_code: budget.nominal_code, area_id: to.record_id }

        assert_equal to, budget.reload.area
      end

      test "clearing the area detaches the budget" do
        sign_in @user

        area = create_reimbursements_area(name: "Cogito")
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

        patch :update, params: { id: budget.record_id, name: budget.name,
                                 nominal_code: budget.nominal_code, area_id: "" }

        assert_nil budget.reload.area
      end

      # The <select> offers store.areas_for_year (year- AND centre-scoped)
      # while area_id writes unscoped, where "" means detach. So whenever the
      # budget's own area is outside the rendered set the select read
      # "— none —", and ANY Save — one changing only the notes — nilled a link
      # nobody touched.
      test "the area select offers the budget's own area even from another year" do
        sign_in @user
        this_year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2026", active: true)
        next_year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2027")
        area = create_reimbursements_area(name: "Cogito", financial_year: next_year)
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

        get :edit, params: { id: budget.record_id }

        assert_response :success
        assert_equal this_year, assigns(:selected_financial_year)
        assert_select "select#area_id option[value=?][selected]", area.record_id
      end

      test "an ordinary Save keeps a link to an area outside the selected year" do
        sign_in @user
        ::Reimbursements::FinancialYear.create!(label: "Fringe 2026", active: true)
        next_year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2027")
        area = create_reimbursements_area(name: "Cogito", financial_year: next_year)
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

        # Post what the RENDERED form posts, so this cannot pass by typing an
        # area_id the browser would never have sent.
        get :edit, params: { id: budget.record_id }
        selected = css_select("select#area_id option[selected]").first
        posted = selected ? selected["value"] : ""

        patch :update, params: { id: budget.record_id, name: budget.name,
                                 nominal_code: budget.nominal_code,
                                 notes: "Only the notes changed", area_id: posted }

        budget.reload
        assert_equal "Only the notes changed", budget.notes
        assert_equal area, budget.area, "a Save touching only the notes must not detach the area"
      end

      # --- Owners on an area-bound budget ------------------------------------
      # The area owns and its budgets inherit, so Budget#owners READS the area's
      # owners while sync_owner_ids! WRITES the budget's own rows. An editable
      # owners fieldset here would therefore read one table and write another:
      # ownership is edited on the AREA, and this form must not offer the list
      # at all (nor let owner_ids reach the store) for an area-bound budget.

      test "an area-bound budget's owners are read-only, with a link to the area" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito")
        area.sync_owner_ids!([ @alice.id ])
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area,
                                              owners: [ @bob ])

        get :edit, params: { id: budget.record_id }

        assert_response :success
        assert_select "input[type=checkbox][name='owner_ids[]']", false,
                      "an area-bound budget must not offer an editable owners list"
        assert_includes response.body, "Alice Owner"
        assert_select "a[href=?]", edit_admin_reimbursements_area_path(area.record_id)
        assert_no_match(/skip budget-owner sign-off/, response.body)
      end

      # Attaching a line to an ownerless area switches its sign-off gate off
      # (OwnerReview.gate_applies? is false with no owners), which is the worst
      # way to get ownership wrong — so the form that can do it says so.
      test "the budget form warns when its area has no owners" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito")
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area,
                                              owners: [ @bob ])

        get :edit, params: { id: budget.record_id }

        assert_response :success
        assert_match(/skip budget-owner sign-off/, response.body)
      end

      test "a Save on an area-bound budget cannot rewrite its own owner rows" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito")
        # Finance moved ownership to Alice on the AREA form; the budget's own
        # row (Bob) is the one the backfill kept so it can be reversed.
        area.sync_owner_ids!([ @alice.id ])
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area,
                                              owners: [ @bob ])

        # Exactly what the old form posted while someone fixed the nominal code:
        # the AREA's owners, on their way into the BUDGET's own rows.
        patch :update, params: { id: budget.record_id, name: budget.name,
                                 nominal_code: "4321", area_id: area.record_id,
                                 owner_ids: [ @alice.record_id ] }

        assert_redirected_to edit_admin_reimbursements_budget_path(budget.record_id)
        assert_equal "4321", budget.reload.nominal_code, "the edit itself must still land"
        assert_equal [ @bob.record_id ], budget.own_owners.reload.map(&:record_id),
                     "the posted owner list must be ignored, not written to own_owners"
        assert_equal [ @alice.record_id ], budget.owner_ids, "the area still owns"
      end

      test "a Save on a budget in an ownerless area cannot destroy its own owner rows" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito")
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area,
                                              owners: [ @bob ])

        # An ownerless area renders nothing ticked, so any Save posted an empty
        # list — and [] compiles to where.not(person_id: []) i.e. WHERE 1=1,
        # wiping the last record of who owned the line.
        patch :update, params: { id: budget.record_id, name: budget.name,
                                 nominal_code: budget.nominal_code,
                                 area_id: area.record_id, owner_ids: [ "" ] }

        assert_equal [ @bob.record_id ], budget.own_owners.reload.map(&:record_id)
      end

      test "a budget with no area keeps its editable owners fieldset" do
        sign_in @user

        get :edit, params: { id: @props.record_id }

        assert_response :success
        assert_select "fieldset legend", text: "Owners"
        assert_select "input[type=checkbox][name='owner_ids[]'][value=#{@bob.record_id}]"

        patch :update, params: { id: @props.record_id, name: "Props", nominal_code: "4000",
                                 budget_type: "Expense", active: "1",
                                 owner_ids: [ @bob.record_id ] }

        assert_equal [ @bob.record_id ], @props.reload.own_owners.map(&:record_id)
        assert_equal [ @bob.record_id ], @props.owner_ids
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
        # 2dp, not the BigDecimal's own "800.0" — the input sits beside
        # figures reimbursements_money prints to the penny.
        assert_select "input[name=amount][value=?]", "800.00"
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

      private

      # Real SQL count for one render of the overview (schema + cached queries
      # excluded), so the preload guarantee is measured rather than assumed.
      def overview_query_count
        count = 0
        counter = ->(*, payload) do
          count += 1 unless payload[:cached] || payload[:name] == "SCHEMA"
        end
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get :overview }
        count
      end

      # --- Creating one budget by hand ---------------------------------------

      test "new renders the form" do
        sign_in @user

        get :new

        assert_response :success
      end

      test "create makes a budget in the selected year" do
        _, next_year = seed_two_years
        sign_in @user

        assert_difference -> { ::Reimbursements::Budget.count }, 1 do
          post :create, params: { year: next_year.key, name: "Late addition", nominal_code: "4200",
                                  budget_type: "Expense", initial_budget: "£1,200", active: "1",
                                  owner_ids: [ @alice.record_id ] }
        end

        budget = ::Reimbursements::Budget.find_by(name: "Late addition")
        assert_redirected_to edit_admin_reimbursements_budget_path(budget.record_id)
        assert_equal next_year, budget.financial_year
        assert_equal ::Reimbursements::CostCentre.default, budget.cost_centre
        # "£1,200" must reach the decimal column parsed, not as a string AR
        # would cast to 0.
        assert_equal BigDecimal("1200"), budget.initial_budget
        assert_equal [ @alice.record_id ], budget.owner_ids
      end

      test "create rejects a blank name without writing" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          post :create, params: { name: "", nominal_code: "4200", budget_type: "Expense" }
        end

        assert_response :unprocessable_entity
      end

      # --- Financial-year selector -------------------------------------------

      test "index shows the selected year's budgets, not every year's" do
        this_year, next_year = seed_two_years
        sign_in @user

        get :index, params: { year: next_year.key }

        assert_equal [ "Next year props" ], assigns(:budgets).map(&:name)
        assert_not_includes assigns(:budgets).map(&:name), "Props"
        assert_equal next_year, assigns(:selected_financial_year)
        # Both years appear as selector links.
        assert_includes response.body, this_year.label
      end

      test "index defaults to the active year" do
        this_year, = seed_two_years
        sign_in @user

        get :index

        assert_equal this_year, assigns(:selected_financial_year)
        assert_includes assigns(:budgets).map(&:name), "Props"
        assert_not_includes assigns(:budgets).map(&:name), "Next year props"
      end

      test "an unknown year falls back to the active year and says so" do
        this_year, = seed_two_years
        sign_in @user

        get :index, params: { year: "fringe-1999" }

        assert_response :success
        assert_equal this_year, assigns(:selected_financial_year)
        # flash.now is swept by the time a controller test can read `flash`, so
        # assert on what the operator actually sees.
        assert_match(/no financial year called .*fringe-1999/, response.body)
      end

      test "the overview scopes to the selected year" do
        _, next_year = seed_two_years
        sign_in @user

        get :overview, params: { year: next_year.key }

        assert_response :success
        names = assigns(:rollups).flat_map { |rollup| rollup.budgets.map(&:name) }
        assert_equal [ "Next year props" ], names
      end

      test "the selector is hidden while only one year exists" do
        ::Reimbursements::FinancialYear.create!(label: "Fringe 2026", active: true)
        sign_in @user

        get :index

        assert_response :success
        assert_no_match(/Financial year:/, response.body)
      end

      # The live year (holding the budgets seeded in setup) plus a draft year
      # with one budget of its own.
      def seed_two_years
        this_year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2026", active: true)
        next_year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2027")
        [ @props, @income ].each { |budget| budget.update!(financial_year: this_year) }
        create_reimbursements_budget(name: "Next year props", nominal_code: "4000")
          .update!(financial_year: next_year)
        [ this_year, next_year ]
      end

      # An area holding one Expense budget with a paid expense and a linked EUSA
      # actual: one of everything the overview's two rollups walk.
      def seed_budget_with_actual(index)
        area = create_reimbursements_area(name: "Area #{index}", initial_budget: 2000)
        budget = create_reimbursements_budget(name: "Extra #{index}", nominal_code: "42#{index}",
                                              area: area, initial_budget: 100)
        expense = create_reimbursements_expense(budget: budget, receipt: false,
                                                status: ::Reimbursements::Status::PAID)
        ::Reimbursements::EusaActual.create!(expense: expense, debit: BigDecimal("5"),
                                            nominal_code: budget.nominal_code)
      end
    end
  end
end
