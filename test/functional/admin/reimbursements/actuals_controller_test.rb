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

      assert_csv_download("actuals")
    end

    test "index CSV export has a header row and one data row per actual" do
      sign_in @user

      get :index, format: :csv

      rows = CSV.parse(response.body)
      assert_equal [ "Date", "Type", "Description", "Amount", "Budget", "Linked expense", "Period",
                     "Status" ],
                   rows.first
      assert_equal 4, rows.size, "header + three actuals"

      # The expense-linked debit row resolves the expense's auto-number.
      exp_row = rows.find { |r| r[2] == "Alice Producer" }
      assert_equal %w[2026-05-13 Debit], exp_row.values_at(0, 1)
      assert_equal "123.45", exp_row[3]
      assert_equal "42", exp_row[5]
      assert_equal "03", exp_row[6]
      assert_equal "", exp_row[7].to_s, "an ordinary row has no reconciliation status"

      # The budget-linked credit row resolves the budget name.
      bud_row = rows.find { |r| r[2] == "Box office" }
      assert_equal "Credit", bud_row[1]
      assert_equal "-500.0", bud_row[3], "income is signed negative (see the export's Amount note)"
      assert_equal "Props", bud_row[4]
    end

    # Amount was unsigned, so a naive SUM() over a mixed export added income to
    # spend, and an offset pair counted twice its value instead of zero. Income
    # is now negative and both offset legs are labelled, so the column sums to
    # net spend.
    test "index CSV export signs the amount so income subtracts from spend" do
      sign_in @user

      get :index, format: :csv

      rows = CSV.parse(response.body, headers: true)
      debit = rows.find { |r| r["Description"] == "Alice Producer" }
      credit = rows.find { |r| r["Description"] == "Box office" }
      assert_equal BigDecimal("123.45"), BigDecimal(debit["Amount"])
      assert_equal BigDecimal("-500.0"), BigDecimal(credit["Amount"]),
                   "a credit is income, so it must not add to spend"
    end

    test "index CSV export marks both legs of an offsetting pair, and they sum to zero" do
      create_offsetting_pair
      sign_in @user

      get :index, params: { include_offsets: "1" }, format: :csv

      rows = CSV.parse(response.body, headers: true)
      legs = rows.select { |r| r["Status"] == "Offset" }
      assert_equal 2, legs.size, "an included offset pair is flagged on both legs"
      assert_equal BigDecimal("0"), legs.sum { |r| BigDecimal(r["Amount"]) },
                   "a cross-linked pair contributes nothing to a SUM of the column"
    end

    test "index CSV export neutralises formula-injected narrative text" do
      create_reimbursements_actual(nominal_code: "600000", period: "05",
                                   narrative: "=1+1", date: Date.new(2026, 7, 1),
                                   debit: BigDecimal("9.99"))
      sign_in @user

      get :index, format: :csv

      rows = CSV.parse(response.body)
      injected = rows.find { |r| r[6] == "05" }
      assert_equal "'=1+1", injected[2]
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

    # --- Offsetting rows ---------------------------------------------------

    # An accrual and its reversal, cross-linked by the reconcile wizard.
    def create_offsetting_pair
      accrual = create_reimbursements_actual(
        nominal_code: "331300", period: "04", narrative: "Venue hire accrual",
        date: Date.new(2026, 6, 2), debit: BigDecimal("500.0"),
        reconciliation_status: ::Reimbursements::EusaActual::STATUS_OFFSET,
        imported_at: Time.utc(2026, 6, 6, 9)
      )
      reversal = create_reimbursements_actual(
        nominal_code: "331300", period: "05", narrative: "Venue hire accrual reversal",
        date: Date.new(2026, 6, 3), debit: nil, credit: BigDecimal("500.0"),
        reconciliation_status: ::Reimbursements::EusaActual::STATUS_OFFSET,
        offset_of: accrual, imported_at: Time.utc(2026, 6, 6, 10)
      )
      accrual.update!(offset_of: reversal)
      [ accrual, reversal ]
    end

    test "offsetting rows are kept out of the working set by default" do
      create_offsetting_pair
      sign_in @user

      get :index

      assert_response :success
      assert_equal [ @unlinked, @linked_budget, @linked_expense ].map(&:record_id),
                   assigns(:actuals).map(&:record_id),
                   "the two offsetting rows net to zero, so they are noise by default"
      assert_equal 2, assigns(:offset_count)
    end

    test "offsetting rows can be shown on request and are badged" do
      accrual, reversal = create_offsetting_pair
      sign_in @user

      get :index, params: { include_offsets: "1" }

      assert_response :success
      assert_includes assigns(:actuals).map(&:record_id), accrual.record_id
      assert_includes assigns(:actuals).map(&:record_id), reversal.record_id
      assert_includes response.body, "Offset"
    end

    test "the offsetting filter carries through to the CSV export" do
      create_offsetting_pair
      sign_in @user

      get :index, format: :csv
      assert_equal 4, CSV.parse(response.body).size, "header + the three non-offsetting rows"

      get :index, params: { include_offsets: "1" }, format: :csv
      assert_equal 6, CSV.parse(response.body).size, "header + all five rows"
    end

    # --- Convert an actual into a From-EUSA expense ------------------------

    test "an unlinked debit row offers a create-expense button" do
      sign_in @user
      get :index

      assert_response :success
      assert_includes response.body, new_expense_admin_reimbursements_actual_path(@unlinked.record_id)
    end

    test "an offsetting row never offers a create-expense button" do
      accrual, = create_offsetting_pair
      sign_in @user

      get :index, params: { include_offsets: "1" }

      assert_response :success
      assert_not_includes response.body,
                          new_expense_admin_reimbursements_actual_path(accrual.record_id)
    end

    test "an already-linked row offers no create-expense button" do
      sign_in @user
      get :index

      assert_response :success
      assert_not_includes response.body,
                          new_expense_admin_reimbursements_actual_path(@linked_expense.record_id)
    end

    test "new_expense prefills the form from the ledger row" do
      sign_in @user
      get :new_expense, params: { id: @unlinked.record_id }

      assert_response :success
      assert_equal ::Reimbursements::Expense::TYPE_FROM_EUSA, assigns(:form).expense_type
      assert_equal BigDecimal("42.0"), assigns(:form).amount_decimal
      assert_equal "Sundry", assigns(:form).description
    end

    test "new_expense preselects the budget when the nominal code maps to exactly one" do
      only_budget = create_reimbursements_budget(name: "Venue", nominal_code: "500000")
      sign_in @user

      get :new_expense, params: { id: @unlinked.record_id }

      assert_response :success
      assert_equal only_budget.record_id, assigns(:form).budget_record_id
    end

    test "new_expense leaves the budget blank when the nominal code is ambiguous" do
      create_reimbursements_budget(name: "Venue A", nominal_code: "500000")
      create_reimbursements_budget(name: "Venue B", nominal_code: "500000")
      sign_in @user

      get :new_expense, params: { id: @unlinked.record_id }

      assert_response :success
      assert_nil assigns(:form).budget_record_id, "the operator picks between them"
    end

    test "new_expense refuses an offsetting row" do
      accrual, = create_offsetting_pair
      sign_in @user

      get :new_expense, params: { id: accrual.record_id }

      assert_redirected_to admin_reimbursements_actuals_path
      assert_match(/offset/i, flash[:alert])
    end

    test "new_expense refuses a credit row" do
      sign_in @user
      get :new_expense, params: { id: @linked_budget.record_id }

      assert_redirected_to admin_reimbursements_actuals_path
      assert_match(/debit/i, flash[:alert])
    end

    test "new_expense refuses a row already linked to an expense" do
      sign_in @user
      get :new_expense, params: { id: @linked_expense.record_id }

      assert_redirected_to admin_reimbursements_actuals_path
      assert_match(/already/i, flash[:alert])
    end

    test "new_expense 404s for an unknown row" do
      sign_in @user
      get :new_expense, params: { id: "999999" }

      assert_response :not_found
    end

    # A From-EUSA expense records a cost EUSA has already taken from us, so it
    # is created settled: it must never enter the review or BACS batch pipeline.
    test "create_expense creates a Paid From-EUSA expense dated from the ledger row" do
      sign_in @user

      post :create_expense, params: {
        id: @unlinked.record_id,
        reimbursements_expense_form: { budget_record_id: @budget.record_id,
                                       description: "Room hire recharge",
                                       payment_reference: "J000001234" }
      }

      assert_redirected_to admin_reimbursements_actuals_path
      expense = ::Reimbursements::Expense.order(:id).last
      assert_equal ::Reimbursements::Expense::TYPE_FROM_EUSA, expense.expense_type
      assert_equal ::Reimbursements::Status::PAID, expense.status
      assert_equal @unlinked.date, expense.payment_confirmed_date
      assert_equal BigDecimal("42.0"), expense.amount
      assert_equal BigDecimal("42.0"), expense.amount_excl_vat
      assert_equal "Room hire recharge", expense.description
      assert_equal @budget.record_id, expense.budget_record_id
      assert_nil expense.person, "a cost EUSA levied directly has no payee to reimburse"
      assert_empty expense.receipts
      assert_nil expense.batch_id
    end

    test "create_expense cross-links the row to the expense it created" do
      sign_in @user

      post :create_expense, params: {
        id: @unlinked.record_id,
        reimbursements_expense_form: { budget_record_id: @budget.record_id,
                                       description: "Room hire recharge",
                                       payment_reference: "J000001234" }
      }

      expense = ::Reimbursements::Expense.order(:id).last
      assert_equal [ expense.record_id ], @unlinked.reload.linked_expense_ids
      assert_not_predicate @unlinked, :convertible_to_expense?, "and can't be converted twice"
    end

    test "create_expense re-renders the form when the budget is missing" do
      sign_in @user

      assert_no_difference -> { ::Reimbursements::Expense.count } do
        post :create_expense, params: {
          id: @unlinked.record_id,
          reimbursements_expense_form: { budget_record_id: "", description: "Room hire",
                                         payment_reference: "J000001234" }
        }
      end

      assert_response :unprocessable_entity
      assert assigns(:form).errors[:budget_record_id].present?
      assert_empty @unlinked.reload.linked_expense_ids
    end

    test "create_expense rejects a budget that no longer exists" do
      sign_in @user

      assert_no_difference -> { ::Reimbursements::Expense.count } do
        post :create_expense, params: {
          id: @unlinked.record_id,
          reimbursements_expense_form: { budget_record_id: "999999", description: "Room hire",
                                         payment_reference: "J000001234" }
        }
      end

      assert_response :unprocessable_entity
      assert_match(/no longer exists/i, assigns(:form).errors[:budget_record_id].to_sentence)
    end

    test "create_expense refuses an offsetting row" do
      accrual, = create_offsetting_pair
      sign_in @user

      assert_no_difference -> { ::Reimbursements::Expense.count } do
        post :create_expense, params: {
          id: accrual.record_id,
          reimbursements_expense_form: { budget_record_id: @budget.record_id,
                                         description: "x", payment_reference: "y" }
        }
      end

      assert_redirected_to admin_reimbursements_actuals_path
      assert_match(/offset/i, flash[:alert])
    end

    test "the amount always comes from the ledger row, not the posted form" do
      sign_in @user

      post :create_expense, params: {
        id: @unlinked.record_id,
        reimbursements_expense_form: { budget_record_id: @budget.record_id,
                                       description: "Room hire", payment_reference: "J1",
                                       amount: "9999.99", expense_type: "Reimbursement" }
      }

      expense = ::Reimbursements::Expense.order(:id).last
      assert_equal BigDecimal("42.0"), expense.amount, "the ledger row is the source of truth"
      assert_equal ::Reimbursements::Expense::TYPE_FROM_EUSA, expense.expense_type
    end

    test "conversion is gated by the finance permission" do
      sign_in users(:committee)

      get :new_expense, params: { id: @unlinked.record_id }
      assert_response :forbidden

      post :create_expense, params: { id: @unlinked.record_id }
      assert_response :forbidden
    end
  end
  end
end
