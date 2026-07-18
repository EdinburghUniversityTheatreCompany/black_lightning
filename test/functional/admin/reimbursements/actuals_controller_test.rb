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

      @expense = create_reimbursements_expense(auto_number: 42, description: "Fake blood")
      @budget = create_reimbursements_budget(name: "Props")

      @linked_expense = create_reimbursements_actual(
        nominal_code: "439999", period: "03", narrative: "Alice Producer",
        date: Date.new(2026, 5, 13), debit: BigDecimal("123.45"), expense: @expense,
        imported_at: Time.utc(2026, 5, 20, 10)
      )
      @linked_budget = create_reimbursements_actual(
        nominal_code: "250000", period: "03", narrative: "Box office",
        date: Date.new(2026, 5, 14), debit: nil, credit: BigDecimal("500.0"), budget: @budget,
        imported_at: Time.utc(2026, 5, 20, 11)
      )
      @unlinked = create_reimbursements_actual(
        nominal_code: "500000", period: "04", narrative: "Sundry",
        date: Date.new(2026, 6, 1), debit: BigDecimal("42.0"),
        imported_at: Time.utc(2026, 6, 5, 9)
      )
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
      assert_equal [ @unlinked, @linked_budget, @linked_expense ].map(&:record_id),
                   assigns(:actuals).map(&:record_id)
      assert_includes response.body, "Alice Producer"
      assert_includes response.body, "Box office"
      assert_includes response.body, "Sundry"
    end

    test "a legacy row with no imported_at sorts by its transaction date instead" do
      ::Reimbursements::EusaActual.delete_all
      recent_import = create_reimbursements_actual(narrative: "Recent import",
                                                   date: Date.new(2020, 1, 1),
                                                   imported_at: Time.utc(2026, 7, 1))
      legacy = create_reimbursements_actual(narrative: "Legacy row",
                                            date: Date.new(2026, 6, 15), imported_at: nil)
      old_import = create_reimbursements_actual(narrative: "Old import",
                                                date: Date.new(2026, 1, 1),
                                                imported_at: Time.utc(2020, 1, 1))
      sign_in @user

      assert_nothing_raised { get :index }

      assert_response :success
      assert_equal [ recent_import, legacy, old_import ].map(&:record_id),
                   assigns(:actuals).map(&:record_id),
                   "the legacy row's transaction date fallback slots it between the two imported rows"
    end

    # Newest-imported first with 50/page; distinct imported_at timestamps make
    # which row lands on which page deterministic.
    def seed_paged_actuals(count)
      ::Reimbursements::EusaActual.delete_all
      (1..count).map do |n|
        create_reimbursements_actual(narrative: "Row #{format('%03d', n)}",
                                     imported_at: Time.utc(2026, 6, (n % 28) + 1))
      end
    end

    test "index pages the list at 50 per page" do
      seed_paged_actuals(60)
      sign_in @user

      get :index

      assert_equal 50, assigns(:actuals).size
    end

    test "index page 2 returns the remaining slice, not page 1's rows" do
      seed_paged_actuals(60)
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
      assert_includes response.body, edit_admin_reimbursements_expense_edit_path(@expense.record_id)
    end

    test "filters by period" do
      sign_in @user
      get :index, params: { period: "04" }

      assert_response :success
      assert_equal [ @unlinked.record_id ], assigns(:actuals).map(&:record_id)
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
      ::Reimbursements::EusaActual.delete_all
      sign_in @user
      get :index

      assert_response :success
      assert_empty assigns(:actuals)
      assert_includes response.body, "No EUSA Actuals imported yet."
    end
  end
  end
end
