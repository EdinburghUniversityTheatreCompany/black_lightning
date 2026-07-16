require "test_helper"

module Admin
  module Reimbursements
  class ActualsControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    setup do
      finance = Role.create!(name: "Business Manager")
      finance.permissions << Permission.create(action: "manage", subject_class: "reimbursements_finance")
      users(:member).add_role("Business Manager")
      @user = users(:member)

      @linked_expense = airtable_eusa_actual_record(
        id: "recActExp", nominal_code: "439999", period: "03", narrative: "Alice Producer",
        date: "2026-05-13", debit: 123.45, linked_expense: [ "recExp1" ],
        imported_at: "2026-05-20T10:00:00Z"
      )
      @linked_budget = airtable_eusa_actual_record(
        id: "recActBud", nominal_code: "250000", period: "03", narrative: "Box office",
        date: "2026-05-14", debit: nil, credit: 500.0, linked_budget: [ "recBud1" ],
        imported_at: "2026-05-20T11:00:00Z"
      )
      @unlinked = airtable_eusa_actual_record(
        id: "recActNone", nominal_code: "500000", period: "04", narrative: "Sundry",
        date: "2026-06-01", debit: 42.0, imported_at: "2026-06-05T09:00:00Z"
      )

      rebuild_store(eusa_actuals: [ @linked_expense, @linked_budget, @unlinked ])
    end

    teardown do
      BaseController.store_builder = -> { ::Reimbursements::Store.new }
    end

    def rebuild_store(eusa_actuals: [])
      @store, @client = build_fake_store(eusa_actuals: eusa_actuals)
      BaseController.store_builder = -> { @store }
    end

    # --- Auth gating -------------------------------------------------------

    test "requires sign-in" do
      get :index
      assert_redirected_to new_user_session_path
    end

    test "denies members without the finance permission" do
      sign_in users(:committee)
      get :index
      assert_response :forbidden
    end

    test "the producer portal permission alone does not grant finance access" do
      producer_role = Role.create!(name: "Producer")
      producer_role.permissions << Permission.create(action: "access", subject_class: "reimbursements")
      submitter = users(:member_with_phone_number)
      submitter.add_role("Producer")
      sign_in submitter

      # The period-filtered route is gated the same as the bare index.
      get :index, params: { period: "03" }

      assert_response :forbidden
    end

    # --- Index -------------------------------------------------------------

    test "lists every imported actual, newest imported first" do
      sign_in @user
      get :index

      assert_response :success
      assert_equal %w[recActNone recActBud recActExp], assigns(:actuals).map(&:record_id)
      assert_includes response.body, "Alice Producer"
      assert_includes response.body, "Box office"
      assert_includes response.body, "Sundry"
    end

    # Newest-imported first with 50/page; distinct imported_at timestamps make
    # which row lands on which page deterministic.
    def rebuild_paged_store(count)
      actuals = (1..count).map do |n|
        airtable_eusa_actual_record(id: "recAct#{n}", narrative: "Row #{format('%03d', n)}",
                                    imported_at: format("2026-06-%02dT00:00:00Z", (n % 28) + 1))
      end
      rebuild_store(eusa_actuals: actuals)
    end

    test "index pages the list at 50 per page" do
      rebuild_paged_store(60)
      sign_in @user

      get :index

      assert_equal 50, assigns(:actuals).size
    end

    test "index page 2 returns the remaining slice, not page 1's rows" do
      rebuild_paged_store(60)
      sign_in @user

      get :index
      page1 = assigns(:actuals).map(&:record_id)

      get :index, params: { page: 2 }
      page2 = assigns(:actuals).map(&:record_id)

      assert_equal 10, page2.size
      assert_empty(page1 & page2, "page 2 must not repeat any page 1 rows")
    end

    test "shows the linked-to state per row" do
      sign_in @user
      get :index

      assert_response :success
      assert_includes response.body, "Expense"
      assert_includes response.body, "Budget"
      assert_includes response.body, "Unlinked"
    end

    test "links an expense-linked actual to its finance edit page" do
      sign_in @user
      get :index

      assert_response :success
      assert_includes response.body, edit_admin_reimbursements_expense_edit_path("recExp1")
    end

    test "filters by period" do
      sign_in @user
      get :index, params: { period: "04" }

      assert_response :success
      assert_equal %w[recActNone], assigns(:actuals).map(&:record_id)
    end

    test "offers the distinct periods as filter options" do
      sign_in @user
      get :index

      assert_response :success
      assert_equal %w[03 04], assigns(:periods)
    end

    # --- CSV export --------------------------------------------------------

    test "index CSV export answers a text/csv download named for today" do
      sign_in @user
      get :index, format: :csv

      assert_response :success
      assert_includes response.media_type, "text/csv"
      assert_match(/attachment/, response.headers["Content-Disposition"])
      assert_match(/reimbursements-actuals-\d{4}-\d{2}-\d{2}\.csv/, response.headers["Content-Disposition"])
    end

    test "index CSV export has a header row and one data row per actual" do
      # Load the linked expense + budget so the CSV resolves their references.
      expense = airtable_expense_record(id: "recExp1", auto_number: 42, description: "Fake blood")
      budget = airtable_budget_record(id: "recBud1", name: "Props")
      @store, @client = build_fake_store(
        eusa_actuals: [ @linked_expense, @linked_budget, @unlinked ],
        expenses: [ expense ], budgets: [ budget ]
      )
      BaseController.store_builder = -> { @store }
      sign_in @user

      get :index, format: :csv

      rows = CSV.parse(response.body)
      assert_equal [ "Date", "Type", "Description", "Amount", "Budget", "Linked expense", "Period" ], rows.first
      assert_equal 4, rows.size, "header + three actuals"

      # The expense-linked debit row resolves the expense's auto-number.
      exp_row = rows.find { |r| r[2] == "Alice Producer" }
      assert_equal %w[2026-05-13 Debit], exp_row.values_at(0, 1)
      assert_equal "123.45", exp_row[3]
      assert_equal "42", exp_row[5]
      assert_equal "03", exp_row[6]

      # The budget-linked credit row resolves the budget name.
      bud_row = rows.find { |r| r[2] == "Box office" }
      assert_equal "Credit", bud_row[1]
      assert_equal "500.0", bud_row[3]
      assert_equal "Props", bud_row[4]
    end

    test "index CSV export carries the period filter, exporting only that period" do
      sign_in @user
      get :index, params: { period: "04" }, format: :csv

      rows = CSV.parse(response.body)
      assert_equal 2, rows.size, "header + the single period-04 actual"
      assert_includes response.body, "Sundry"
      assert_not_includes response.body, "Alice Producer"
    end

    test "renders an empty state when nothing has been imported" do
      rebuild_store(eusa_actuals: [])
      sign_in @user
      get :index

      assert_response :success
      assert_empty assigns(:actuals)
      assert_includes response.body, "No EUSA Actuals imported yet."
    end
  end
  end
end
