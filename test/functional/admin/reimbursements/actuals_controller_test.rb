require "test_helper"

module Admin
  module Reimbursements
  class ActualsControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    # A store whose actual-to-expense link write always fails: the conversion's
    # second write dying after the expense was created.
    class UnlinkableStore < ::Reimbursements::DatabaseStore
      def link_actual_to_expense!(_actual_id, _expense_id)
        raise "blip"
      end
    end

    # A store that hands the controller a STALE row: the copy the before_action
    # checks still looks unlinked while the stored row has already been
    # converted. This is what a second click on a double-submitted form sees.
    class StaleActualStore < ::Reimbursements::DatabaseStore
      def find_actual(record_id)
        super&.tap { |actual| actual.expense_id = nil }
      end
    end

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

    # store_builder is a class attribute, so a test that swaps in a failing store
    # must hand the real one back or every later test inherits it.
    teardown do
      BaseController.store_builder = BaseController::DEFAULT_STORE_BUILDER
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

    # ?state=all, because the page now OPENS on the rows needing attention (see
    # the state-filter tests below). This one is about the ledger's contents
    # and its ordering, so it asks for the whole thing.
    test "lists every imported actual, newest imported first" do
      sign_in @user
      get :index, params: { state: "all" }

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
      # Seeded here because the test used to render ONE unlinked row and pass
      # on the page's chrome: the Finance sidebar's old "Expenses" link carried
      # the word "Expense" until the nav was regrouped, so a bare body match was
      # satisfied whatever the rows said.
      budget = create_reimbursements_budget(name: "Ticket income", budget_type: "Income")
      expense = create_reimbursements_expense(budget: budget, description: "Linked claim")
      create_reimbursements_eusa_actual(narrative: "Paid by BACS", debit: 10,
                                        expense_id: expense.record_id)
      create_reimbursements_eusa_actual(narrative: "Box office", credit: 20,
                                        budget_id: budget.record_id)

      sign_in @user
      # The full ledger: it opens on the rows needing attention, which is
      # exactly the view a LINKED row is filtered out of.
      get :index, params: { state: "all" }

      assert_response :success
      # The BADGES in the "Linked to" column, not a bare body match: reading the
      # whole page let the sidebar satisfy this (its "Expenses" link carried the
      # word until the nav was regrouped), so it passed whatever the rows said.
      ledger = css_select("table").map(&:text).join(" ")
      assert_includes ledger, "Expense"
      assert_includes ledger, "Budget"
      assert_includes ledger, "Unlinked"
    end

    test "links an expense-linked actual to its finance edit page" do
      sign_in @user
      get :index, params: { state: "all" }

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

      get :index, params: { state: "all" }, format: :csv

      rows = CSV.parse(response.body)
      assert_equal [ "Date", "Type", "Description", "Amount", "Budget", "Linked expense", "Period",
                     "Status", "Cost centre", "Area" ],
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

    # Finance re-imports this file and sums the Amount column. Unsigned, that sum
    # adds income to spend and counts an offset pair at twice its value instead
    # of zero; signed (income negative, both offset legs labelled) it is net
    # spend.
    test "index CSV export signs the amount so income subtracts from spend" do
      sign_in @user

      get :index, params: { state: "all" }, format: :csv

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

    # --- The needs-attention filter ----------------------------------------
    #
    # The ledger is read after a reconcile to find what is LEFT to do, and a
    # row already attached to a claim or a budget offers no action at all — 17
    # of the 50 rows on the first page were inert. So the page opens on the
    # leftovers, with the whole ledger one click away.

    test "the index opens on the rows that need attention" do
      sign_in @user

      get :index

      assert_response :success
      assert_equal ::Admin::Reimbursements::ActualsController::STATE_NEEDS_ATTENTION,
                   assigns(:state)
      assert_equal [ @unlinked.record_id ], assigns(:actuals).map(&:record_id)
    end

    test "the state rides in the URL so the full ledger is a link" do
      sign_in @user

      get :index, params: { state: "all" }

      assert_response :success
      assert_equal 3, assigns(:actuals).size
      assert_includes response.body, "Show only rows needing attention"
    end

    test "an unrecognised state falls back to the leftovers rather than 500ing" do
      sign_in @user

      get :index, params: { state: "wibble" }

      assert_response :success
      assert_equal ::Admin::Reimbursements::ActualsController::STATE_NEEDS_ATTENTION,
                   assigns(:state)
    end

    test "a split row counts as finished with, not as needing attention" do
      budget = create_reimbursements_budget(name: "Box office", budget_type: "Income")
      credit = create_reimbursements_eusa_actual(credit: BigDecimal("100"), narrative: "Stripe")
      ::Reimbursements::ActualAllocation.create!(eusa_actual: credit, budget: budget,
                                                 amount: BigDecimal("100"))
      sign_in @user

      get :index

      assert_not_includes assigns(:actuals).map(&:record_id), credit.record_id
    end

    test "the counts describe the rows on screen, so the switch says what it would show" do
      sign_in @user

      get :index

      assert_equal 1, assigns(:needs_attention_count)
      assert_equal 3, assigns(:matching_count)
    end

    # An old link or bookmark asking for the offsets must still get them: an
    # offsetting leg is never a row needing attention, so answering with the
    # needs-attention view would be the control lying.
    test "asking for the offsets alone opens the full ledger" do
      create_offsetting_pair
      sign_in @user

      get :index, params: { include_offsets: "1" }

      assert_equal ::Admin::Reimbursements::ActualsController::STATE_ALL, assigns(:state)
      assert_equal 5, assigns(:actuals).size
    end

    test "the hidden-offsets sentence links to the rows it describes" do
      create_offsetting_pair
      sign_in @user

      get :index, params: { state: "all" }

      assert_response :success
      assert_includes response.body,
                      CGI.escapeHTML(admin_reimbursements_actuals_path(state: "all",
                                                                       include_offsets: "1"))
      assert_includes response.body, "can be undone"
    end

    # --- Search -------------------------------------------------------------

    test "searches the narrative" do
      sign_in @user

      get :index, params: { state: "all", search: "box off" }

      assert_equal [ @linked_budget.record_id ], assigns(:actuals).map(&:record_id)
    end

    test "searches the amount, with the separators a person types stripped" do
      sign_in @user

      get :index, params: { state: "all", search: "£123.45" }

      assert_equal [ @linked_expense.record_id ], assigns(:actuals).map(&:record_id)
    end

    test "search carries through to the CSV export" do
      sign_in @user

      get :index, params: { state: "all", search: "Sundry" }, format: :csv

      assert_equal 2, CSV.parse(response.body).size, "header + the one matching row"
    end

    test "search and period narrow together" do
      sign_in @user

      get :index, params: { state: "all", period: "03", search: "Sundry" }

      assert_empty assigns(:actuals)
    end

    test "offsetting rows are kept out of the working set by default" do
      create_offsetting_pair
      sign_in @user

      get :index, params: { state: "all" }

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

      get :index, params: { state: "all" }, format: :csv
      assert_equal 4, CSV.parse(response.body).size, "header + the three non-offsetting rows"

      get :index, params: { include_offsets: "1" }, format: :csv
      assert_equal 6, CSV.parse(response.body).size, "header + all five rows"
    end

    # --- Undoing an offset --------------------------------------------------
    #
    # A false positive in the pairing heuristic stamps real spend as noise,
    # hiding it from the ledger view and every rollup. There has to be a way
    # back that doesn't need a console.

    test "unoffset clears the stamp and the cross-link on both legs" do
      accrual, reversal = create_offsetting_pair
      sign_in @user

      post :unoffset, params: { id: accrual.record_id }

      assert_redirected_to admin_reimbursements_actuals_path
      [ accrual, reversal ].each do |leg|
        leg.reload
        assert_not_predicate leg, :offset?
        assert_nil leg.offset_of_id
      end
      assert_equal 2, ::Reimbursements::EusaActual.where(id: [ accrual.id, reversal.id ]).count,
                   "both rows survive: finance needs the audit trail either way"
    end

    test "unoffset works from either leg" do
      accrual, reversal = create_offsetting_pair
      sign_in @user

      post :unoffset, params: { id: reversal.record_id }

      assert_not_predicate accrual.reload, :offset?
      assert_not_predicate reversal.reload, :offset?
    end

    # An un-offset debit row is ordinary spend again, so it can be converted.
    test "an un-offset debit row becomes convertible again" do
      accrual, = create_offsetting_pair
      sign_in @user

      post :unoffset, params: { id: accrual.record_id }

      assert_predicate accrual.reload, :convertible_to_expense?
    end

    test "unoffset keeps the operator's filters" do
      accrual, = create_offsetting_pair
      sign_in @user

      post :unoffset, params: { id: accrual.record_id, period: "04", include_offsets: "1" }

      assert_redirected_to admin_reimbursements_actuals_path(period: "04", include_offsets: "1")
    end

    test "unoffset refuses a row that is not marked offsetting" do
      sign_in @user

      post :unoffset, params: { id: @unlinked.record_id }

      assert_redirected_to admin_reimbursements_actuals_path
      assert_match(/not marked/i, flash[:alert])
    end

    test "unoffset 404s for an unknown row" do
      sign_in @user
      post :unoffset, params: { id: "999999" }

      assert_response :not_found
    end

    test "unoffset is gated by the finance permission" do
      accrual, = create_offsetting_pair
      sign_in users(:committee)

      post :unoffset, params: { id: accrual.record_id }

      assert_response :forbidden
      assert_predicate accrual.reload, :offset?
    end

    test "an offsetting row offers the undo button" do
      accrual, = create_offsetting_pair
      sign_in @user

      get :index, params: { include_offsets: "1" }

      assert_response :success
      assert_includes response.body, unoffset_admin_reimbursements_actual_path(accrual.record_id)
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

    # The budget is checked against the list this page's own picker offered, so
    # a line deleted between the page loading and the submit is a fixable form
    # error rather than a foreign-key 500 on create_expense!.
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
      assert_match(/no longer available/i, assigns(:form).errors[:budget_record_id].to_sentence)
      assert_empty @unlinked.reload.linked_expense_ids
    end

    # And one still on the books but retired. It satisfies the foreign key, so
    # this never raised — it quietly booked an EUSA charge against a budget
    # finance had taken out of use.
    test "create_expense rejects a budget that has been deactivated" do
      retired = create_reimbursements_budget(name: "Last year's props", nominal_code: "4900",
                                             active: false)
      sign_in @user

      assert_no_difference -> { ::Reimbursements::Expense.count } do
        post :create_expense, params: {
          id: @unlinked.record_id,
          reimbursements_expense_form: { budget_record_id: retired.record_id,
                                         description: "Room hire",
                                         payment_reference: "J000001234" }
        }
      end

      assert_response :unprocessable_entity
      assert_match(/no longer available/i, assigns(:form).errors[:budget_record_id].to_sentence)
      assert_empty @unlinked.reload.linked_expense_ids
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

    # --- Conversion is one unit ---------------------------------------------
    #
    # The "already converted" guard is state-based, so the expense and its link
    # must commit together: a Paid expense whose link write failed leaves the row
    # unlinked and still offering "Create expense", and the next click
    # double-counts the same EUSA charge.

    test "a conversion whose link write fails creates no expense at all" do
      BaseController.store_builder = ->(**) { UnlinkableStore.new }
      sign_in @user

      assert_no_difference -> { ::Reimbursements::Expense.count } do
        assert_raises(RuntimeError) do
          post :create_expense, params: {
            id: @unlinked.record_id,
            reimbursements_expense_form: { budget_record_id: @budget.record_id,
                                           description: "Room hire recharge",
                                           payment_reference: "J000001234" }
          }
        end
      end

      assert_empty @unlinked.reload.linked_expense_ids
    end

    # The convertibility check has to be re-taken inside the writing
    # transaction: a second click whose before_action read the row before the
    # first click committed would otherwise convert it again.
    test "a conversion racing another one is refused rather than duplicated" do
      BaseController.store_builder = ->(**) { StaleActualStore.new }
      ::Reimbursements::EusaActual.find(@unlinked.id).update!(expense: @expense)
      sign_in @user

      assert_no_difference -> { ::Reimbursements::Expense.count } do
        post :create_expense, params: {
          id: @unlinked.record_id,
          reimbursements_expense_form: { budget_record_id: @budget.record_id,
                                         description: "Room hire recharge",
                                         payment_reference: "J000001234" }
        }
      end

      assert_redirected_to admin_reimbursements_actuals_path
      assert_match(/already/i, flash[:alert])
      assert_equal [ @expense.record_id ], @unlinked.reload.linked_expense_ids,
                   "the first conversion's link stands"
    end

    test "conversion is gated by the finance permission" do
      sign_in users(:committee)

      get :new_expense, params: { id: @unlinked.record_id }
      assert_response :forbidden

      post :create_expense, params: { id: @unlinked.record_id }
      assert_response :forbidden
    end

    # --- Manual link to a claim ---------------------------------------------
    #
    # The matcher is deliberately conservative and leaves a row unmatched rather
    # than inventing a link, so a human needs a way to finish the job. It is
    # also the backstop under the international window: an international claim's
    # stored amount is only finance's estimate until the payment clears, and a
    # rate that moved far enough lands outside even the widened tolerance.

    def international_claim(amount: BigDecimal("230.00"))
      create_reimbursements_expense(
        auto_number: 77, budget: @budget, status: ::Reimbursements::Status::SUBMITTED,
        amount: amount, amount_excl_vat: amount, description: "Festival insurance",
        payment_method: ::Reimbursements::Expense::PAYMENT_METHOD_INTERNATIONAL,
        foreign_amount: BigDecimal("266.69"),
        foreign_currency: ::Reimbursements::Expense::CURRENCY_EUR
      )
    end

    test "link_expense lists unpaid claims, closest amount first" do
      international_claim(amount: BigDecimal("41.00"))
      sign_in @user

      get :link_expense, params: { id: @unlinked.record_id }

      assert_response :success
      # The £41 claim is 1.00 from the £42 row; the £12.50 fixture claim is far off.
      assert_equal 77, assigns(:candidates).first.auto_number
    end

    # --- What Link to claim offers, and in what order ------------------------
    #
    # The list was every claim in the portal ordered by amount alone — 37 of
    # them, Draft and Rejected included, with a Rejected one ranked third.

    test "link_expense offers no draft or rejected claim" do
      draft = create_reimbursements_expense(auto_number: 90, budget: @budget,
                                            status: ::Reimbursements::Status::DRAFT,
                                            amount: BigDecimal("42.00"),
                                            amount_excl_vat: BigDecimal("42.00"))
      rejected = create_reimbursements_expense(auto_number: 91, budget: @budget,
                                               status: ::Reimbursements::Status::REJECTED,
                                               amount: BigDecimal("42.00"),
                                               amount_excl_vat: BigDecimal("42.00"))
      sign_in @user

      get :link_expense, params: { id: @unlinked.record_id }

      numbers = assigns(:candidates).map(&:auto_number)
      assert_not_includes numbers, draft.auto_number,
                          "a draft is a claim its submitter has not finished writing"
      assert_not_includes numbers, rejected.auto_number,
                          "a rejected claim is one finance refused to pay"
    end

    test "link_expense still offers a Pending, Approved or Submitted claim" do
      pending_claim = create_reimbursements_expense(auto_number: 92, budget: @budget,
                                                    status: ::Reimbursements::Status::PENDING,
                                                    amount: BigDecimal("42.00"),
                                                    amount_excl_vat: BigDecimal("42.00"))
      approved = create_reimbursements_expense(auto_number: 93, budget: @budget,
                                               status: ::Reimbursements::Status::APPROVED,
                                               amount: BigDecimal("42.00"),
                                               amount_excl_vat: BigDecimal("42.00"))
      sign_in @user

      get :link_expense, params: { id: @unlinked.record_id }

      numbers = assigns(:candidates).map(&:auto_number)
      assert_includes numbers, pending_claim.auto_number
      assert_includes numbers, approved.auto_number
    end

    # The narrative is routinely "BACS PAYMENT KIRSTY TOLMIE" — the strongest
    # evidence on the row — while amount-closeness alone ranked her claim
    # sixth behind four unrelated ones that happened to be nearer.
    test "a claim whose payee the narrative names outranks a closer amount" do
      @unlinked.update!(narrative: "BACS PAYMENT KIRSTY TOLMIE")
      kirsty = create_reimbursements_person(name: "Kirsty Tolmie", email: "kirsty@example.com")
      named = create_reimbursements_expense(auto_number: 94, budget: @budget, person: kirsty,
                                            status: ::Reimbursements::Status::SUBMITTED,
                                            amount: BigDecimal("500.00"),
                                            amount_excl_vat: BigDecimal("500.00"))
      create_reimbursements_expense(auto_number: 95, budget: @budget,
                                    status: ::Reimbursements::Status::SUBMITTED,
                                    amount: BigDecimal("42.00"),
                                    amount_excl_vat: BigDecimal("42.00"))
      sign_in @user

      get :link_expense, params: { id: @unlinked.record_id }

      assert_equal named.auto_number, assigns(:candidates).first.auto_number
    end

    # A ledger row belongs to one pot and a claim resolves one through its
    # budget, so a candidate from the other centre is almost certainly the
    # wrong answer — and the list said nothing about it.
    test "link_expense names each candidate's cost centre" do
      centre = ::Reimbursements::CostCentre.default
      placed = create_reimbursements_budget(name: "Placed", cost_centre: centre)
      create_reimbursements_expense(auto_number: 96, budget: placed,
                                    status: ::Reimbursements::Status::SUBMITTED,
                                    amount: BigDecimal("42.00"),
                                    amount_excl_vat: BigDecimal("42.00"))
      sign_in @user

      get :link_expense, params: { id: @unlinked.record_id }

      assert_response :success
      assert_includes response.body, centre.name
    end

    # --- What Create expense offers ------------------------------------------

    test "new_expense lists the budgets on this row's nominal code first" do
      matching = create_reimbursements_budget(name: "Sundries", nominal_code: "500000")
      sign_in @user

      get :new_expense, params: { id: @unlinked.record_id }

      assert_response :success
      label, options = assigns(:budget_groups).first
      assert_includes label, "500000"
      assert_includes options.map(&:last), matching.record_id
      # An order, not a filter: every other line is still offerable.
      assert_includes assigns(:budget_groups).last.last.map(&:last), @budget.record_id
    end

    test "new_expense prints each budget's nominal code in its label" do
      sign_in @user

      get :new_expense, params: { id: @unlinked.record_id }

      assert_response :success
      assert(assigns(:budget_groups).flat_map(&:last).all? { |label, _| label.include?("·") })
    end

    # The MARKUP, not just the ivar: a bare collection with group_method
    # renders one OPTION PER GROUP — the label as its text and the whole array
    # as its value — which looks plausible on the page and offers no budget at
    # all. Only `as: :grouped_select` really groups.
    test "new_expense renders real optgroups, each holding its budgets" do
      create_reimbursements_budget(name: "Sundries", nominal_code: "500000")
      sign_in @user

      get :new_expense, params: { id: @unlinked.record_id }

      assert_response :success
      groups = css_select("select#reimbursements_expense_form_budget_record_id optgroup")
      assert_equal 2, groups.size
      assert_includes groups.first["label"], "500000"
      assert(groups.all? { |group| group.css("option").any? },
             "an optgroup with no options offers nothing")
      assert_includes css_select("select#reimbursements_expense_form_budget_record_id option")
                      .map { |option| option.text.strip }.join(" "), "Sundries"
    end

    test "link_expense refuses a row that is already linked" do
      sign_in @user

      get :link_expense, params: { id: @linked_expense.record_id }

      assert_redirected_to admin_reimbursements_actuals_path
      assert_match(/already linked/, flash[:alert])
    end

    test "link_expense refuses a credit row" do
      sign_in @user

      get :link_expense, params: { id: @linked_budget.record_id }

      assert_redirected_to admin_reimbursements_actuals_path
      assert_match(/Only a debit row/, flash[:alert])
    end

    test "confirm_link settles the claim and links the row" do
      claim = international_claim
      sign_in @user

      post :confirm_link, params: { id: @unlinked.record_id, expense_id: claim.record_id }

      settled = claim.reload
      assert_equal ::Reimbursements::Status::PAID, settled.status
      assert_equal Date.new(2026, 6, 1), settled.payment_confirmed_date
      assert_equal claim.id, @unlinked.reload[:expense_id]
    end

    # The whole point of linking an international claim: its stored amount was
    # the estimate, and the budget would otherwise quote it forever.
    test "confirm_link corrects an international claim to what EUSA charged" do
      claim = international_claim
      sign_in @user

      post :confirm_link, params: { id: @unlinked.record_id, expense_id: claim.record_id }

      assert_equal BigDecimal("42.0"), claim.reload.amount
      assert_match(/corrected to what EUSA charged/, flash[:notice])
    end

    test "confirm_link leaves a UK claim's amount alone" do
      sign_in @user

      post :confirm_link, params: { id: @unlinked.record_id, expense_id: @expense.record_id }

      assert_equal BigDecimal("12.5"), @expense.reload.amount, "a UK amount is not an estimate"
      assert_no_match(/corrected/, flash[:notice])
    end

    test "confirm_link on a vanished claim changes nothing" do
      sign_in @user

      post :confirm_link, params: { id: @unlinked.record_id, expense_id: "999999" }

      assert_match(/no longer exists/, flash[:alert])
      assert_nil @unlinked.reload[:expense_id]
    end

    test "confirm_link refuses a row that is already linked" do
      claim = international_claim
      sign_in @user

      post :confirm_link, params: { id: @linked_expense.record_id, expense_id: claim.record_id }

      assert_match(/already linked/, flash[:alert])
      assert_equal ::Reimbursements::Status::SUBMITTED, claim.reload.status
    end
  end
  end
end
