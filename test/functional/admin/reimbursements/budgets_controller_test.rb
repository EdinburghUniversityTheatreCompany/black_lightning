require "test_helper"

module Admin
  module Reimbursements
    class BudgetsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      # The overview's out-of-scope sentence, pinned whole: it stops a finance
      # user misreading two figures over different sets of lines, so every
      # clause must hold on both bases and for a line of either type.
      OUT_OF_SCOPE_WARNING =
        "1 of 2 lines shown. 1 line in another year or cost centre, left out of the totals " \
        "below. The not-yet-allocated figure is worked out over every line the area holds.".freeze

      setup do
        @user = users(:member)
        grant_finance_permission(@user)

        @alice = create_reimbursements_person(name: "Alice Owner", email: "alice@example.com")
        @bob = create_reimbursements_person(name: "Bob Owner", email: "bob@example.com")
        @props = create_reimbursements_budget(name: "Props", nominal_code: "4000", active: true,
                                              initial_budget: 1000, owners: [ @alice ])
        @income = create_reimbursements_budget(name: "Ticket income", budget_type: "Income")
        @forecast = @props.forecasts.create!(amount: 800, date: Date.new(2026, 5, 1),
                                             reason: "Initial projection")
        # Committed 300 (Approved 150 + Paid 150 excl-VAT), paid 150, remaining
        # 800 - 300 = 500.
        create_reimbursements_expense(budget: @props, status: ::Reimbursements::Status::APPROVED,
                                      amount_excl_vat: 150, amount: 180, receipt: false)
        create_reimbursements_expense(budget: @props, status: ::Reimbursements::Status::PAID,
                                      amount_excl_vat: 150, amount: 180, receipt: false)
      end

      # --- Auth gating -------------------------------------------------------

      test "the producer portal permission alone does not open the finance pages" do
        submitter = users(:member_with_phone_number)
        grant_producer_permission(submitter)
        sign_in submitter

        get :edit, params: { id: @props.record_id }
        assert_response :forbidden

        get :overview
        assert_response :forbidden
      end

      # --- Index -------------------------------------------------------------

      # A Pending 275 (pipeline) and a reconciled EUSA debit of 161 on the Paid
      # expense, so every rollup on @props has a distinct figure.
      def seed_pipeline_and_eusa_debit
        create_reimbursements_expense(budget: @props, status: ::Reimbursements::Status::PENDING,
                                      amount_excl_vat: 275, amount: 330, receipt: false)
        paid = @props.expenses.find { |e| e.status == ::Reimbursements::Status::PAID }
        ::Reimbursements::EusaActual.create!(expense: paid, nominal_code: "4000",
                                            debit: BigDecimal("161.00"))
      end

      # Type, Visible, Pipeline and Paid (portal) are kept off the index for width; the CSV
      # carries them.
      test "index shows each line's rollups, not the cut columns" do
        sign_in @user
        seed_pipeline_and_eusa_debit

        get :index

        assert_response :success
        assert_equal 2, assigns(:budgets).size
        headers = css_select("thead th").map { |th| th.text.strip }
        assert_equal [ "Budget", "Initial", "Projected", "Committed", "EUSA actual", "Expected outturn",
                       "Remaining", "Variance", "Owners", "" ], headers
        # @props: forecast 800, committed 300, remaining 500, and EUSA actual 161 from the seed above.
        %w[800 300 500 161].each { |figure| assert_includes response.body, "£#{figure}.00" }
        assert_select "td.text-right", text: /161/
      end

      test "a hidden line is tagged after its name rather than in a column" do
        @props.update!(active: false)
        sign_in @user

        get :index

        assert_select "tr#budget_#{@props.record_id} td:first-child span", text: "(hidden)"
      end

      # Two years, so a link that adds the selected year when the URL names none fails here.
      test "All is an explicit empty cost_centre= the page's links keep; with none at all they stay bare" do
        create_second_reimbursements_cost_centre
        seed_two_years
        sign_in @user

        get :index, params: { cost_centre: "" }

        assert_nil assigns(:selected_cost_centre)
        assert_select "[aria-label='Cost centre'] a[aria-current]", text: "All"
        assert_select "[aria-label='Cost centre'] a[href=?]", admin_reimbursements_budgets_path(cost_centre: "")
        assert_select "nav[aria-label='Budget views'] a[href=?]",
                      overview_admin_reimbursements_budgets_path(cost_centre: "")
        assert_select "a[href=?]", new_admin_reimbursements_budget_path(cost_centre: ""), text: "New budget"

        get :index

        assert_select "nav[aria-label='Budget views'] a[href=?]", overview_admin_reimbursements_budgets_path
        assert_select "a[href=?]", new_admin_reimbursements_budget_path, text: "New budget"
      end

      test "the row a save came back for is highlighted" do
        sign_in @user

        get :index, params: { budget: @props.record_id }

        assert_select "tr#budget_#{@props.record_id} td.bg-yellow-50", count: 10
        assert_select "tr#budget_#{@props.record_id} td.bg-white", count: 0
      end

      test "every cell of a row greys on hover, the pinned Edit cell included" do
        sign_in @user

        get :index

        assert_select "tr#budget_#{@props.record_id} td[class~='group-hover:bg-gray-50']", count: 10
      end

      def seed_many_budgets(count)
        ::Reimbursements::Expense.delete_all
        ::Reimbursements::BudgetForecast.delete_all
        ::Reimbursements::BudgetOwner.delete_all
        ::Reimbursements::Budget.delete_all
        (1..count).each { |n| create_reimbursements_budget(name: format("Budget %03d", n)) }
      end

      test "index lists every budget on one page" do
        seed_many_budgets(60)
        sign_in @user

        get :index, params: { page: 2 }

        assert_equal 60, assigns(:budgets).size
        assert_includes response.body, "Budget 001"
        assert_includes response.body, "Budget 060"
        assert_includes response.body, "60 budgets"
      end

      test "flags a visible budget with no owner, never an owned or hidden one" do
        sign_in @user
        @income.destroy!
        # Hidden overhead lines (payroll, NI, contracts) never have a producer owner, so flagging
        # them would drown the visible budgets that need chasing.
        create_reimbursements_budget(name: "Payroll", active: false)

        get :index

        assert_includes response.body, "Alice Owner"
        assert_not_includes response.body, "No owner"

        create_reimbursements_budget(name: "Unowned category")

        get :index

        assert_includes response.body, "No owner"
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
        assert_includes response.body, "Over budget"
        # Initial and committed render.
        assert_includes response.body, "1,000"
        assert_includes response.body, "1,400"
      end

      test "flags 'Over original budget' (not 'Over budget') when the forecast still covers the overspend" do
        sign_in @user
        # Committed past the initial figure, but a raised forecast still
        # leaves some remaining.
        revised = create_reimbursements_budget(name: "Revised set", initial_budget: 1000,
                                               owners: [ @alice ])
        revised.forecasts.create!(amount: 1400, date: Date.new(2026, 5, 1), reason: "revised up")
        create_reimbursements_expense(budget: revised, status: ::Reimbursements::Status::APPROVED,
                                      amount_excl_vat: 1200, amount: 1440, receipt: false)

        get :index

        assert_response :success
        assert_includes response.body, "Over original budget"
        assert_select "span", text: "Over budget", count: 0
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
        @income.update!(active: false)

        get :index, format: :csv

        rows = CSV.parse(response.body)
        assert_equal [ "Budget", "Nominal code", "Type", "Visible", "Initial", "Current forecast",
                       "Projected", "Committed", "Pipeline", "Paid (portal)", "EUSA actual",
                       "Expected outturn", "Remaining", "Variance", "Owners", "Cost centre",
                       "Area" ], rows.first
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
        assert_equal %w[Income Hidden], rows.find { |r| r[0] == "Ticket income" }.values_at(2, 3)
      end

      # The glossary block above the table is the one definition; a title= note drifts from it.
      test "index column headings carry no tooltip of their own" do
        sign_in @user

        get :index

        assert_select "thead [title]", count: 0
        assert_select "details dt", text: "Expected outturn"
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

      # +area+'s rowgroup heading on the grouped index: agreed total,
      # allocation and what is left, which must reconcile left to right.
      def area_heading(area)
        css_select("[data-area='#{area.record_id}'] th[scope=rowgroup]").sole.text.squish
      end

      test "the grouped index prints a netted allocation as its two halves, never a bare negative" do
        sign_in @user
        area = create_reimbursements_area(name: "Committee", initial_budget: 1_000,
                                          budget_basis: "net")
        create_reimbursements_budget(name: "Committee: Socials", area: area, initial_budget: 400)
        create_reimbursements_budget(name: "Committee: Raffle", area: area, initial_budget: 800,
                                     budget_type: "Income")

        get :index

        assert_response :success
        heading = area_heading(area)
        assert_includes heading, "Allocated £400.00 of spend less £800.00 of income"
        assert_includes heading, "£1,400.00 not yet allocated"
        # 1,000 - (-400) = 1,400 would reconcile only by subtracting a negative.
        assert_not_includes heading, "-£400.00"
      end

      test "the grouped index states a spend cap's allocation as one figure" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito show", initial_budget: 1_000)
        create_reimbursements_budget(name: "Cogito show: Marketing", area: area,
                                     initial_budget: 400)
        create_reimbursements_budget(name: "Cogito show: Tickets", area: area,
                                     initial_budget: 800, budget_type: "Income")

        get :index

        assert_response :success
        heading = area_heading(area)
        # Nothing is netted here, so there are no halves to state.
        assert_includes heading, "Allocated £400.00"
        assert_not_includes heading, "of income"
        assert_includes heading, "£600.00 not yet allocated"
      end

      test "the grouped index names no agreed total when nobody agreed one" do
        sign_in @user
        area = create_reimbursements_area(name: "Unbudgeted area")
        create_reimbursements_budget(name: "Unbudgeted area: Set", area: area,
                                     initial_budget: 400)

        get :index

        assert_response :success
        heading = area_heading(area)
        # "Agreed total (expenses) -" reads as a claim about expenses rather
        # than as a plan nobody has set yet.
        assert_not_includes heading, "Agreed total"
        assert_not_includes heading, "not yet allocated"
        # A £0.00 here would read as fully overspent.
        assert_not_includes heading, "Remaining"
        assert_includes heading, "Allocated £400.00"
      end

      # A permanent "X of X lines shown" would be noise on every ordinary area.
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

      # --- Overview (nominal-code rollup) ------------------------------------

      # Its column notes come from the Glossary block, not title= tooltips that drift from it.
      test "overview defines Expected outturn in its glossary block, not in a tooltip" do
        sign_in @user

        get :overview

        assert_select "details dt", text: "Expected outturn"
        assert_select "thead [title]", count: 0
      end

      test "overview groups budgets by nominal code with a per-code subtotal" do
        sign_in @user
        # @props is 4000 with initial 1000. Amounts are chosen so no single row
        # carries a subtotal's figure, or the assertions would pin no grouping.
        create_reimbursements_budget(name: "Set", nominal_code: "4000", initial_budget: 500)
        create_reimbursements_budget(name: "Travel", nominal_code: "4100", initial_budget: 200)
        create_reimbursements_budget(name: "Digs", nominal_code: "4100", initial_budget: 350)

        get :overview

        assert_response :success
        assert_includes response.body, "Nominal code 4000"
        assert_includes response.body, "Nominal code 4100"
        assert_includes response.body, "Subtotal 4000"
        assert_includes response.body, "Subtotal 4100"
        # Subtotals: 4000 = 1000 + 500; 4100 = 200 + 350.
        assert_includes response.body, "1,500"
        assert_includes response.body, "550"
        # Grand total initial = 1000 + 500 + 200 + 350 = 2050 (Income has none).
        assert_includes response.body, "2,050"
        assert_includes response.body, "Grand total"
      end

      test "neither page's query count grows with the number of budgets or areas" do
        sign_in @user
        # The baseline holds one of everything: Rails skips a preload with nothing to
        # load, which would make the two renders different shapes, not sizes.
        seed_budget_with_actual(0)
        get :index
        get :overview # warm anything cached per process
        baseline = %i[index overview].map { |action| count_queries { get action } }

        9.times { |i| seed_budget_with_actual(i + 1) }

        assert_equal baseline, %i[index overview].map { |action| count_queries { get action } }
      end

      test "overview totals expense and income budgets separately, never as one figure" do
        sign_in @user
        # Expense initial 1000 (@props) + 9000, income 8000. One grand total
        # would read 18,000, which is neither spend nor net.
        create_reimbursements_budget(name: "Lighting", nominal_code: "4200",
                                     initial_budget: 9000)
        create_reimbursements_budget(name: "Programme ads", nominal_code: "8100",
                                     budget_type: "Income", initial_budget: 8000)

        get :overview

        assert_response :success
        assert_includes response.body, "Grand total (Expense budgets)"
        assert_includes response.body, "Grand total (Income budgets)"
        assert_includes response.body, "£10,000.00"
        assert_includes response.body, "£8,000.00"
        assert_not_includes response.body, "£18,000.00"
      end

      test "overview marks each row's budget type" do
        sign_in @user
        create_reimbursements_budget(name: "Programme ads", nominal_code: "8100",
                                     budget_type: "Income", initial_budget: 8000)

        get :overview

        assert_response :success
        # A Type cell per row, so an income line can't be read as spend.
        assert_select "table.table thead th", text: "Type"
        assert_select "table.table tbody td", text: "Income"
        assert_select "table.table tbody td", text: "Expense"
        assert_select "th", text: "Remaining"
        assert_select "th", text: "Variance"
      end

      # --- The overview as a health check -------------------------------------

      test "the overview badges an over-budget line, as the index does" do
        sign_in @user
        get :overview

        assert_includes response.body, "No line is over budget"

        over = create_reimbursements_budget(name: "Overspent", nominal_code: "4321",
                                            initial_budget: 100)
        create_reimbursements_expense(budget: over, status: ::Reimbursements::Status::APPROVED,
                                      amount: 200, amount_excl_vat: 200)

        get :overview

        assert_response :success
        assert_includes response.body, "Over budget"
        assert_equal 1, assigns(:over_budget_count)
      end

      # Unattributed income makes the net negative, so the count leads.
      test "the summary leads on the count, so a net credit does not read as alarm" do
        sign_in @user
        ::Reimbursements::EusaActual.create!(nominal_code: "9999", narrative: "Box office",
                                             credit: BigDecimal("500.00"))

        get :overview

        assert_response :success
        assert_includes response.body, "1 EUSA ledger row"
        assert_includes response.body, "debits less credits"
      end

      # --- Remaining is never blank without a reason -------------------------

      test "a line with no forecast and no initial budget says so instead of a dash" do
        sign_in @user
        ::Reimbursements::Budget.create!(name: "Unplanned", nominal_code: "4322")

        get :index

        assert_response :success
        assert_includes response.body, "No budget set"
      end

      test "overview lists unattributed actuals, including spend on a budgeted code" do
        sign_in @user
        # 4000 is budgeted (@props) but this row links to nothing, so no
        # budget counts it; a code-based list would lose it entirely.
        ::Reimbursements::EusaActual.create!(nominal_code: "4000", narrative: "Unlinked hire",
                                             debit: BigDecimal("1250.00"))
        ::Reimbursements::EusaActual.create!(nominal_code: "9999", narrative: "Mystery charge",
                                             ref: "AUDIT-7", period: "06", debit: BigDecimal("42.00"))
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
        assert_not_includes response.body, "Every EUSA actual is attributed to a budget."
        assert_equal [ BigDecimal("1292"), 2 ], [ assigns(:unattributed_total), assigns(:unattributed_count) ]
        # The summary links to the card, and the card to the EUSA Actuals ledger (not Reconcile,
        # which has no per-row linking), each row to its own ref and period on it.
        assert_includes response.body, "attributed to no budget"
        assert_includes response.body, "#unattributed-actuals"
        assert_includes response.body, "EUSA Actuals ledger"
        assert_includes response.body, admin_reimbursements_actuals_path(state: "needs_attention")
        assert_includes response.body,
                        CGI.escapeHTML(admin_reimbursements_actuals_path(
                                         state: "needs_attention", period: "06", search: "AUDIT-7"
                                       ))
      end

      test "overview shows a friendly note when every actual is attributed" do
        sign_in @user
        get :overview

        assert_response :success
        # The card title renders either way; the sentence only when empty.
        assert_includes response.body, "Actuals not attributed to any budget"
        assert_includes response.body, "Every EUSA actual is attributed to a budget."
        assert_empty assigns(:unattributed_by_code)
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
        # The area heading links to the area's own page.
        assert_select "th[scope=rowgroup] a.font-semibold", text: "Cogito"
        assert_select "th[scope=rowgroup] a[href=?]",
                      admin_reimbursements_area_path(area.record_id)
        # 750 = 400 + 350, a figure no single row carries.
        assert_includes response.body, "Subtotal Cogito (Expense)"
        assert_includes response.body, "£750.00"
        # The agreed figure and what is left to split (5000 - 750).
        assert_includes response.body, "Agreed total (expenses) £5,000.00"
        assert_includes response.body, "£4,250.00 not yet allocated"
        # Props and the income line are in no area, and still appear under a
        # heading.
        assert_includes response.body, "Not in an area"
        assert_not_includes response.body, "No budgets to group."
      end

      test "the overview orders its area cards as the index orders its groups" do
        sign_in @user
        %w[Zeta Ábel].each do |name|
          create_reimbursements_budget(name: "Set", area: create_reimbursements_area(name: name))
        end

        get :overview

        assert_equal %w[Ábel Zeta], assigns(:area_rollups).map(&:name)
      end

      test "overview allocates an area on its declared basis, never netting its subtotals" do
        sign_in @user
        # An agreed total, so the figure the basis governs is reached.
        area = create_reimbursements_area(name: "Cogito", initial_budget: 1000)
        create_reimbursements_budget(name: "Cogito marketing", nominal_code: "4300", area: area,
                                     initial_budget: 410)
        create_reimbursements_budget(name: "Cogito tickets", nominal_code: "8100", area: area,
                                     budget_type: "Income", initial_budget: 805)

        get :overview

        assert_response :success
        spend, income = assigns(:area_rollups).sole.by_type
        assert_equal BigDecimal("410"), spend.initial
        assert_equal BigDecimal("805"), income.initial
        assert_includes response.body, "Subtotal Cogito (Expense)"
        assert_includes response.body, "Subtotal Cogito (Income)"
        # 1,215 is neither the show's spend nor its income, so nothing says it.
        assert_not_includes response.body, "£1,215.00"
        # A spend cap by default: income buys no room, so 1,000 - 410.
        assert_includes response.body, "Agreed total (expenses) £1,000.00"
        assert_includes response.body, "£590.00 not yet allocated"

        # A net allowance: 1,000 - 410 + 805. The subtotals are unchanged; the
        # basis governs the area's own arithmetic only.
        area.update!(budget_basis: "net")
        get :overview

        assert_response :success
        assert_equal [ BigDecimal("410"), BigDecimal("805") ],
                     assigns(:area_rollups).sole.by_type.map(&:initial)
        assert_includes response.body, "Agreed total (net) £1,000.00"
        assert_includes response.body, "£1,395.00 not yet allocated"
        assert_not_includes response.body, "£1,215.00"
      end

      test "an area with no agreed total shows no figure, never a zero" do
        sign_in @user
        # The area and its line share no substring.
        area = create_reimbursements_area(name: "Backfilled show")
        create_reimbursements_budget(name: "Props ledger", nominal_code: "4300", area: area,
                                     initial_budget: 400)

        get :overview

        assert_response :success
        assert_select "th[scope=rowgroup] a.font-semibold", text: "Backfilled show"
        # "Agreed total (expenses) £0.00" would read as fully overspent.
        assert_not_includes response.body, "Agreed total"
        assert_not_includes response.body, "not yet allocated"
      end

      test "with no agreed total the out-of-scope warning claims no allocation figure" do
        this_year, next_year = seed_two_years
        sign_in @user
        area = create_reimbursements_area(name: "Cogito", financial_year: this_year)
        create_reimbursements_budget(name: "Cogito marketing", nominal_code: "4300", area: area,
                                     initial_budget: 400, financial_year: this_year)
        create_reimbursements_budget(name: "Cogito next year", nominal_code: "4300", area: area,
                                     initial_budget: 900, financial_year: next_year)

        get :overview, params: { year: this_year.key }

        assert_response :success
        assert_not_includes response.body, "Cogito next year"
        assert_not_includes response.body, "not yet allocated"
        assert_equal "1 of 2 lines shown. 1 line in another year or cost centre, left out of " \
                     "the totals below.",
                     css_select("span.text-warning").sole.text.squish
      end

      # The sentence states no DIRECTION because, across these four rows, the
      # out-of-scope line reduces, raises or does not move the not-yet-allocated
      # figure. Each row states that figure.
      {
        [ "expenses", "Expense" ] => "£3,700.00",  # 5,000 - 400 - 900: reduced
        [ "expenses", "Income" ] => "£4,600.00",   # 5,000 - 400: not moved at all
        [ "net", "Expense" ] => "£3,700.00",       # 5,000 - 400 - 900: reduced
        [ "net", "Income" ] => "£5,500.00"         # 5,000 - 400 + 900: RAISED
      }.each do |(basis, out_of_scope_type), unallocated|
        test "the out-of-scope warning holds for a #{basis} area losing an #{out_of_scope_type} line" do
          this_year, next_year = seed_two_years
          sign_in @user
          area = create_reimbursements_area(name: "Cogito", financial_year: this_year,
                                            initial_budget: 5000, budget_basis: basis)
          create_reimbursements_budget(name: "Cogito marketing", nominal_code: "4300", area: area,
                                       initial_budget: 400, financial_year: this_year)
          # Reachable by an ordinary edit, and the budget form preserves it
          # deliberately, so the overview has to state it rather than drop it.
          create_reimbursements_budget(name: "Cogito next year", nominal_code: "4300", area: area,
                                       initial_budget: 900, financial_year: next_year,
                                       budget_type: out_of_scope_type)

          get :overview, params: { year: this_year.key }

          assert_response :success
          assert_not_includes response.body, "Cogito next year"
          assert_includes response.body, "#{unallocated} not yet allocated"
          assert_equal OUT_OF_SCOPE_WARNING, css_select("span.text-warning").sole.text.squish
        end
      end

      test "the area card says so when there is nothing to group" do
        sign_in @user
        # Budgets but no areas is not an empty page (they group under "Not in an
        # area"), so the banner is for no budgets at all.
        ::Reimbursements::EusaActual.delete_all
        ::Reimbursements::Expense.destroy_all
        ::Reimbursements::Budget.destroy_all

        get :overview

        assert_response :success
        assert_includes response.body, "No budgets to group."
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
        # The hidden empty field clears the owners when the last is taken off.
        assert_select "fieldset[data-reimbursements-budget-area-target=owners] " \
                      "select#owner_ids[name='owner_ids[]'][multiple].simple-select2"
        assert_select "input[type=hidden][name='owner_ids[]'][value='']"
        assert_select "select#owner_ids option[value=#{@alice.record_id}][selected]"
        assert_select "select#owner_ids option[value=#{@bob.record_id}]"
        assert_select "select#owner_ids option[value=#{@bob.record_id}][selected]", false
      end

      # The Glossary is the one definition; the figures' old hover notes had drifted from it.
      test "edit's read-only figures carry no tooltip of their own" do
        sign_in @user

        get :edit, params: { id: @props.record_id }

        assert_select "dl dd", minimum: 8
        assert_select "dl dd[title]", count: 0
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

      # The breadcrumb is built from the URL, so the id segment must resolve to
      # the record's name.
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

      { "a blank name" => [ { name: "  " }, /Enter a budget name/ ],
        "a blank nominal code" => [ { nominal_code: " " }, /Enter a nominal code/ ],
        "an unknown budget type" => [ { budget_type: "Something else entirely" },
                                      /Choose a valid budget type/ ] }.each do |label, (override, message)|
        test "#{label} is rejected without a write" do
          sign_in @user

          patch :update, params: { id: @props.record_id, name: "Props", nominal_code: "4000",
                                   budget_type: "Expense" }.merge(override)

          assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
          assert_match message, flash[:alert]
          assert_equal %w[Props 4000 Expense], @props.reload.slice(:name, :nominal_code, :budget_type).values
        end
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

        assert_redirected_to admin_reimbursements_budgets_path(budget: @props.record_id, anchor: "budget_#{@props.record_id}")
        @props.reload
        assert_equal "Set & construction", @props.name
        assert_equal "4200", @props.nominal_code
        assert_equal "Split with lighting", @props.notes
        assert_in_delta 1875.5, @props.initial_budget
        assert_equal [ @alice, @bob ].map(&:record_id).sort, @props.owner_ids.sort
        assert @props.active
      end

      test "a Save without active or owners clears both" do
        sign_in @user

        patch :update, params: { id: @props.record_id, name: "Props", nominal_code: "4000",
                                 budget_type: "Expense" }

        @props.reload
        assert_not @props.active
        assert_empty @props.owner_ids
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

      # area_id writes unscoped and "" detaches, so the select must offer the
      # budget's own area or any Save nils it.
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

      # An ownerless area switches its lines' sign-off gate off.
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
        # The area names Alice; Bob is an own row like those the backfill left.
        area.sync_owner_ids!([ @alice.id ])
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area,
                                              owners: [ @bob ])

        # The area's owners, posted towards the budget's own rows.
        patch :update, params: { id: budget.record_id, name: budget.name,
                                 nominal_code: "4321", area_id: area.record_id,
                                 owner_ids: [ @alice.record_id ] }

        assert_redirected_to admin_reimbursements_budgets_path(budget: budget.record_id, anchor: "budget_#{budget.record_id}")
        assert_equal "4321", budget.reload.nominal_code, "the edit itself must still land"
        assert_equal [ @bob.record_id ], budget.own_owners.reload.map(&:record_id),
                     "the posted owner list must be ignored, not written to own_owners"
        assert_equal [ @alice.record_id ], budget.owner_ids, "the area still owns"

        # An empty list reaching sync_owner_ids! is where.not(person_id: []), i.e. WHERE 1=1.
        patch :update, params: { id: budget.record_id, name: budget.name,
                                 nominal_code: "4321", area_id: area.record_id, owner_ids: [ "" ] }

        assert_equal [ @bob.record_id ], budget.own_owners.reload.map(&:record_id)
      end

      # --- Forecast create ---------------------------------------------------

      test "adding a forecast creates a linked Budget Forecasts record" do
        sign_in @user

        assert_difference -> { @props.forecasts.count }, 1 do
          post :forecast, params: { id: @props.record_id, amount: "£1,750.50", date: "2026-06-01",
                                    reason: "Revised up" }
        end

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        created = @props.forecasts.order(:id).last
        assert_in_delta 1750.5, created.amount
        assert_equal Date.new(2026, 6, 1), created.date
        assert_equal "Revised up", created.reason
      end

      { "a missing amount" => { amount: "" }, "a malformed amount" => { amount: "not-a-number" },
        "a malformed date" => { date: "not-a-date" } }.each do |label, override|
        test "a forecast with #{label} is rejected without a write" do
          sign_in @user

          assert_no_difference -> { ::Reimbursements::BudgetForecast.count } do
            post :forecast, params: { id: @props.record_id, amount: "750.50", date: "2026-06-01" }.merge(override)
          end

          assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
          assert_match(/valid amount and date/i, flash[:alert])
        end
      end

      # --- Edit / delete a logged forecast -----------------------------------

      test "edit with ?edit_forecast renders that row as an inline edit form" do
        sign_in @user

        get :edit, params: { id: @props.record_id, edit_forecast: @forecast.record_id }

        assert_response :success
        assert_equal @forecast.record_id, assigns(:editing_forecast_id)
        assert_select "input[name=forecast_id][value=#{@forecast.record_id}]"
        # 2dp, not the BigDecimal's "800.0", like the figures beside it.
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

      test "a forecast from another budget is refused through this budget's URL" do
        # @forecast is linked to @props, so reaching it via @income must be refused.
        sign_in @user

        patch :update_forecast, params: { id: @income.record_id, forecast_id: @forecast.record_id,
                                          amount: "999.00", date: "2026-06-02" }

        assert_redirected_to edit_admin_reimbursements_budget_path(@income.record_id)
        assert_match(/isn't part of this budget/i, flash[:alert])
        assert_in_delta 800, @forecast.reload.amount

        assert_no_difference -> { ::Reimbursements::BudgetForecast.count } do
          delete :delete_forecast, params: { id: @income.record_id, forecast_id: @forecast.record_id }
        end

        assert_redirected_to edit_admin_reimbursements_budget_path(@income.record_id)
        assert_match(/isn't part of this budget/i, flash[:alert])
      end

      private

      # --- Creating one budget by hand ---------------------------------------

      test "create makes a budget in the selected year" do
        _, next_year = seed_two_years
        sign_in @user
        # The curated list suggests, never constrains: 4200 is not on it.
        create_reimbursements_nominal_code(code: "432320", label: "Marketing")

        assert_difference -> { ::Reimbursements::Budget.count }, 1 do
          post :create, params: { year: next_year.key, name: "Late addition", nominal_code: "4200",
                                  budget_type: "Expense", initial_budget: "£1,200", active: "1",
                                  owner_ids: [ @alice.record_id ] }
        end

        budget = ::Reimbursements::Budget.find_by(name: "Late addition")
        assert_redirected_to edit_admin_reimbursements_budget_path(budget.record_id, year: next_year.key)
        assert_equal next_year, budget.financial_year
        assert_equal ::Reimbursements::CostCentre.default, budget.cost_centre
        # "£1,200" must reach the decimal column parsed, not as a string AR
        # would cast to 0.
        assert_equal BigDecimal("1200"), budget.initial_budget
        assert_equal [ @alice.record_id ], budget.owner_ids
        assert_equal "4200", budget.nominal_code
      end

      test "create lands on the centre the form chose, not the page's" do
        termtime = create_second_reimbursements_cost_centre
        fringe = ::Reimbursements::CostCentre.where.not(id: termtime.id).first
        sign_in @user

        post :create, params: { cost_centre: termtime.key, cost_centre_id: fringe.id, name: "Late addition",
                                nominal_code: "4200", budget_type: "Expense", active: "1" }

        budget = ::Reimbursements::Budget.find_by(name: "Late addition")
        assert_equal fringe, budget.cost_centre
        assert_redirected_to edit_admin_reimbursements_budget_path(budget.record_id, cost_centre: fringe.key)
      end

      # --- Owners on a line going INTO an area -------------------------------

      test "create refuses a line going into an area while owners are ticked" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito")
        area.sync_owner_ids!([ @alice.id ])

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          # initial_budget: "" is what a BROWSER posts for an empty number
          # input; omitting it hid the re-render's 500.
          post :create, params: { name: "Marketing", nominal_code: "432320", budget_type: "Expense",
                                  active: "1", area_id: area.record_id, initial_budget: "",
                                  owner_ids: [ @alice.record_id, @bob.record_id ] }
        end

        assert_response :unprocessable_entity
        # flash.now is swept by the time a controller test can read `flash`, so
        # assert on what the operator actually sees.
        assert_match(/takes its owners from the area/, response.body)
        assert_equal [ @alice.record_id ], area.reload.owners.map(&:record_id),
                     "a refusal must not widen the area's own owner list either"
      end

      # --- The curated nominal codes -----------------------------------------

      test "the budget form suggests the curated codes" do
        sign_in @user
        create_reimbursements_nominal_code(code: "432320", label: "Marketing and publicity")

        get :new

        assert_response :success
        assert_select "datalist#nominal-code-suggestions option[value=?]", "432320"
        assert_match(/Marketing and publicity/, response.body)
      end

      test "a retired code still labels the rows that carry it" do
        sign_in @user
        create_reimbursements_nominal_code(code: "432320", label: "Marketing", active: false)

        get :new

        assert_select "datalist#nominal-code-suggestions option[value=?]", "432320", count: 0
        assert_includes ::Reimbursements::NominalCode.labels_for(nil), "432320",
                        "a retired code must still be readable on historical rows"
      end

      test "the overview prints each code's label beside it" do
        sign_in @user
        create_reimbursements_nominal_code(code: "4000", label: "Production materials")

        get :overview

        assert_response :success
        assert_match(/Production materials/, response.body)
      end

      test "create refuses an area from a different cost centre" do
        sign_in @user
        other = create_second_reimbursements_cost_centre
        area = create_reimbursements_area(name: "Cogito", cost_centre: other)

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          post :create, params: { name: "Marketing", nominal_code: "432320", budget_type: "Expense",
                                  active: "1", area_id: area.record_id, initial_budget: "",
                                  cost_centre_id: ::Reimbursements::CostCentre.default.id }
        end

        assert_response :unprocessable_entity
        assert_match(/different cost centre/, response.body)
        assert_match(/Bedlam Termtime/, response.body, "the message has to name which")
      end

      test "create accepts an area in the same cost centre" do
        sign_in @user
        other = create_second_reimbursements_cost_centre
        area = create_reimbursements_area(name: "Cogito", cost_centre: other)

        post :create, params: { name: "Marketing", nominal_code: "432320", budget_type: "Expense",
                                active: "1", area_id: area.record_id, cost_centre_id: other.id }

        budget = ::Reimbursements::Budget.find_by!(name: "Marketing")
        assert_equal area.id, budget.area_id
        assert_equal other.id, budget.cost_centre_id
      end

      # An unstamped area belongs to every centre; inheritance fills the blank.
      test "an area with no cost centre is not refused" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito", cost_centre: nil)

        post :create, params: { name: "Marketing", nominal_code: "432320", budget_type: "Expense",
                                active: "1", area_id: area.record_id }

        assert_equal area.id, ::Reimbursements::Budget.find_by!(name: "Marketing").area_id
      end

      test "the edit form refuses to move a line into another centre's area" do
        sign_in @user
        other = create_second_reimbursements_cost_centre
        area = create_reimbursements_area(name: "Cogito", cost_centre: other)
        @props.update!(cost_centre: ::Reimbursements::CostCentre.default)

        patch :update, params: { id: @props.record_id, name: "Props", nominal_code: "4000",
                                 budget_type: "Expense", active: "1", area_id: area.record_id }

        assert_match(/different cost centre/, flash[:alert])
        assert_nil @props.reload.area_id, "a refused Save must not attach the area"
      end

      # The picker offers only areas area_scope_error would accept.
      test "the edit form offers only areas in the budget's own cost centre" do
        sign_in @user
        other = create_second_reimbursements_cost_centre
        create_reimbursements_area(name: "Termtime show", cost_centre: other)
        create_reimbursements_area(name: "Fringe show", cost_centre: ::Reimbursements::CostCentre.default)
        create_reimbursements_area(name: "Unplaced show", cost_centre: nil)
        @props.update!(cost_centre: ::Reimbursements::CostCentre.default)

        get :edit, params: { id: @props.record_id }

        names = css_select("select#area_id option").map(&:text)
        assert_includes names, "Fringe show"
        assert_includes names, "Unplaced show", "an unstamped area is lenient-scoped into every centre"
        assert_not_includes names, "Termtime show"
      end

      # On new every centre's areas render and the browser filters them by the
      # Cost centre select, which must come first.
      test "the new form tags each area with its cost centre and asks for the centre first" do
        sign_in @user
        other = create_second_reimbursements_cost_centre
        area = create_reimbursements_area(name: "Termtime show", cost_centre: other)
        unplaced = create_reimbursements_area(name: "Unplaced show", cost_centre: nil)

        get :new

        assert_select "select#area_id option[value=?][data-cost-centre-id=?]", area.record_id, other.id.to_s
        assert_select "select#area_id option[value=?]:not([data-cost-centre-id])", unplaced.record_id
        assert_select "select#cost_centre_id[data-reimbursements-budget-area-target=costCentre]"
        assert_operator response.body.index('id="cost_centre_id"'), :<, response.body.index('id="area_id"'),
                        "the cost centre is chosen before the area it narrows"
      end

      test "create inside an area with nobody ticked writes no own-owner rows" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito")
        area.sync_owner_ids!([ @alice.id ])

        post :create, params: { name: "Marketing", nominal_code: "432320", budget_type: "Expense",
                                active: "1", area_id: area.record_id, owner_ids: [ "" ] }

        budget = ::Reimbursements::Budget.find_by!(name: "Marketing")
        assert_redirected_to edit_admin_reimbursements_budget_path(budget.record_id)
        assert_empty budget.own_owners, "the area owns; nothing belongs in the budget's own rows"
        assert_equal [ @alice.record_id ], budget.owner_ids
      end

      test "attaching an area on the edit form refuses while owners are ticked" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito")

        patch :update, params: { id: @props.record_id, name: "Props", nominal_code: "4000",
                                 budget_type: "Expense", active: "1", area_id: area.record_id,
                                 owner_ids: [ @bob.record_id ] }

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id)
        assert_match(/takes its owners from the area/, flash[:alert])
        assert_nil @props.reload.area_id, "the area must not be attached by a refused Save"
        assert_equal [ @alice.record_id ], @props.own_owners.reload.map(&:record_id)
      end

      # An empty list would reach sync_owner_ids! as where.not(person_id: []),
      # i.e. WHERE 1=1, deleting the own rows the backfill left.
      test "attaching an area with nobody ticked keeps the budget's own owner rows" do
        sign_in @user
        area = create_reimbursements_area(name: "Cogito")

        patch :update, params: { id: @props.record_id, name: "Props", nominal_code: "4000",
                                 budget_type: "Expense", active: "1", area_id: area.record_id,
                                 owner_ids: [ "" ] }

        assert_redirected_to admin_reimbursements_budgets_path(budget: @props.record_id, anchor: "budget_#{@props.record_id}")
        @props.reload
        assert_equal area.id, @props.area_id
        assert_equal [ @alice.record_id ], @props.own_owners.map(&:record_id)
      end

      # --- Financial-year selector -------------------------------------------

      test "index shows the selected year's budgets, defaulting to the active year" do
        this_year, next_year = seed_two_years
        sign_in @user

        get :index

        assert_equal this_year, assigns(:selected_financial_year)
        assert_includes assigns(:budgets).map(&:name), "Props"
        assert_not_includes assigns(:budgets).map(&:name), "Next year props"

        get :index, params: { year: next_year.key }

        assert_equal [ "Next year props" ], assigns(:budgets).map(&:name)
        assert_equal next_year, assigns(:selected_financial_year)
        # Both years appear as selector links.
        assert_includes response.body, this_year.label
      end

      test "an unknown year falls back to the active year and says so" do
        this_year, = seed_two_years
        sign_in @user

        get :index, params: { year: "fringe-1999" }

        assert_response :success
        assert_equal this_year, assigns(:selected_financial_year)
        # flash.now is swept before a controller test reads flash.
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

      test "the budget tabs and the index's row links keep the selected year and centre" do
        this_year, = seed_two_years
        other = create_second_reimbursements_cost_centre
        sign_in @user
        scope = { year: this_year.key, cost_centre: other.key }

        get :index, params: scope

        assert_select "nav[aria-label='Budget views'] a[aria-current=page][href=?]",
                      admin_reimbursements_budgets_path(scope), text: "Budgets"
        assert_select "nav[aria-label='Budget views'] a[href=?]",
                      overview_admin_reimbursements_budgets_path(scope), text: "Overview"
        assert_select "a[href=?]", edit_admin_reimbursements_budget_path(@props.record_id, **scope)

        get :overview, params: scope

        assert_select "nav[aria-label='Budget views'] a[href=?]",
                      admin_reimbursements_budgets_path(scope), text: "Budgets"
      end

      test "the selector is hidden while only one year exists" do
        ::Reimbursements::FinancialYear.create!(label: "Fringe 2026", active: true)
        sign_in @user

        get :index

        assert_response :success
        assert_no_match(/Financial year:/, response.body)
      end

      # --- Keeping the page's filters through an edit ---------------------

      test "a saved budget returns to the filtered index at its own row" do
        _, next_year = seed_two_years
        termtime = create_second_reimbursements_cost_centre
        sign_in @user

        patch :update, params: { id: @props.record_id, name: "Props", nominal_code: "4000",
                                 budget_type: "Expense", year: next_year.key,
                                 cost_centre: termtime.key }

        assert_redirected_to admin_reimbursements_budgets_path(
          year: next_year.key, cost_centre: termtime.key, budget: @props.record_id,
          anchor: "budget_#{@props.record_id}"
        )
      end

      test "the edit page's form, back link and forecast form carry the filters" do
        _, next_year = seed_two_years
        termtime = create_second_reimbursements_cost_centre
        sign_in @user
        scope = { year: next_year.key, cost_centre: termtime.key }

        get :edit, params: { id: @props.record_id, **scope }

        assert_select "form[action=?]", admin_reimbursements_budget_path(@props.record_id, **scope)
        assert_select "form[action=?]", forecast_admin_reimbursements_budget_path(@props.record_id, **scope)
        assert_select "a[href=?]", admin_reimbursements_budgets_path(**scope), text: /All budgets/
      end

      test "a forecast added from a filtered edit page comes back to it filtered" do
        termtime = create_second_reimbursements_cost_centre
        sign_in @user

        post :forecast, params: { id: @props.record_id, amount: "900", date: "2026-06-01",
                                  cost_centre: termtime.key }

        assert_redirected_to edit_admin_reimbursements_budget_path(@props.record_id, cost_centre: termtime.key)
      end

      test "the edit page links to the previous and next budget in the index's order" do
        area = create_reimbursements_area(name: "Cogito")
        in_area = create_reimbursements_budget(name: "Zebra", area: area)
        termtime = create_second_reimbursements_cost_centre
        sign_in @user

        # Index order: area lines first (Zebra), then loose lines by name
        # (Props, Ticket income).
        get :edit, params: { id: @props.record_id, cost_centre: termtime.key }
        assert_select "a[rel=prev][href=?]",
                      edit_admin_reimbursements_budget_path(in_area.record_id, cost_centre: termtime.key)
        assert_select "a[rel=next][href=?]",
                      edit_admin_reimbursements_budget_path(@income.record_id, cost_centre: termtime.key)
      end

      test "a line with no neighbours gets no empty neighbours nav" do
        @income.destroy!
        sign_in @user

        get :edit, params: { id: @props.record_id }

        assert_select "nav[aria-label='Neighbouring budgets']", count: 0
      end

      test "the cost-centre selector offers to make the selected centre the default" do
        termtime = create_second_reimbursements_cost_centre
        sign_in @user

        get :index, params: { cost_centre: termtime.key }

        assert_select "form[action=?] button", admin_reimbursements_home_cost_centre_path(cost_centre: termtime.key),
                      text: "Make this my default"
      end

      test "the cost-centre selector names the default on every page, offering a switch elsewhere" do
        termtime = create_second_reimbursements_cost_centre
        fringe = ::Reimbursements::CostCentre.where.not(id: termtime.id).first
        @user.update!(reimbursements_cost_centre: termtime)
        sign_in @user

        { termtime.key => false, nil => false, fringe.key => true }.each do |key, offers_switch|
          get :index, params: { cost_centre: key }.compact

          assert_includes css_select("[aria-label='Cost centre'] span").map { |span| span.text.squish },
                          "Default: #{termtime.name}"
          assert_select "form[action=?] button", admin_reimbursements_home_cost_centre_path, text: "Clear"
          assert_select "button", text: "Make this my default", count: offers_switch ? 1 : 0
        end
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

      # An area holding one Expense budget with a forecast, a paid expense and a linked
      # EUSA actual: one of everything the index and overview walk.
      def seed_budget_with_actual(index)
        area = create_reimbursements_area(name: "Area #{index}", initial_budget: 2000)
        budget = create_reimbursements_budget(name: "Extra #{index}", nominal_code: "42#{index}",
                                              area: area, initial_budget: 100)
        budget.forecasts.create!(amount: 150, date: Date.new(2026, 5, 1), reason: "plan")
        expense = create_reimbursements_expense(budget: budget, receipt: false,
                                                status: ::Reimbursements::Status::PAID)
        ::Reimbursements::EusaActual.create!(expense: expense, debit: BigDecimal("5"),
                                            nominal_code: budget.nominal_code)
      end
    end
  end
end
