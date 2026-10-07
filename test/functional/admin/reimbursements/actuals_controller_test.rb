require "test_helper"

module Admin
  module Reimbursements
  class ActualsControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    # Hands the controller a stale row: the before_action's copy looks unlinked while the stored
    # row is already converted, as a second click on a double-submitted form sees it.
    class StaleActualStore < ::Reimbursements::DatabaseStore
      def find_actual(record_id)
        super&.tap { |actual| actual.expense_id = nil }
      end
    end

    setup do
      grant_finance_permission(users(:member))
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

    # store_builder is a class_attribute: restore it or every later test inherits a swapped store.
    teardown do
      BaseController.store_builder = BaseController::DEFAULT_STORE_BUILDER
    end

    # --- Index -------------------------------------------------------------

    test "the full ledger lists every row newest first, with its link state and actions" do
      sign_in @user
      get :index, params: { state: "all" }

      assert_response :success
      assert_equal [ @unlinked, @linked_budget, @linked_expense ].map(&:record_id),
                   assigns(:actuals).map(&:record_id)
      # The table, not the body: the sidebar's own "Expenses" link used to satisfy a body match.
      ledger = css_select("table").map(&:text).join(" ")
      assert_includes ledger, "Expense"
      assert_includes ledger, "Budget"
      assert_includes ledger, "Unlinked"
      assert_includes response.body, edit_admin_reimbursements_expense_edit_path(@expense.record_id)
      assert_includes response.body, "Show only rows needing attention"
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

      get :index

      assert_response :success
      assert_equal [ recent_import, legacy, old_import ].map(&:record_id),
                   assigns(:actuals).map(&:record_id),
                   "the legacy row's transaction date fallback slots it between the two imported rows"
    end

    # Distinct imported_at timestamps make which row lands on which page deterministic.
    def seed_paged_actuals(count)
      ::Reimbursements::EusaActual.delete_all
      (1..count).map do |n|
        create_reimbursements_actual(narrative: "Row #{format('%03d', n)}",
                                     imported_at: Time.utc(2026, 6, (n % 28) + 1))
      end
    end

    test "index page 2 returns the remaining slice, not page 1's rows" do
      seed_paged_actuals(60)
      sign_in @user

      get :index
      page1 = assigns(:actuals).map(&:record_id)

      get :index, params: { page: 2 }
      page2 = assigns(:actuals).map(&:record_id)

      assert_equal 50, page1.size
      assert_equal 10, page2.size
      assert_empty(page1 & page2, "page 2 must not repeat any page 1 rows")
    end

    test "filters by period" do
      sign_in @user
      get :index, params: { period: "04" }

      assert_response :success
      assert_equal [ @unlinked.record_id ], assigns(:actuals).map(&:record_id)
    end

    # --- CSV export --------------------------------------------------------

    test "index CSV export has a header row and one data row per actual" do
      sign_in @user

      get :index, params: { state: "all" }, format: :csv

      assert_csv_download("actuals")
      rows = CSV.parse(response.body)
      assert_equal [ "Date", "Type", "Description", "Amount", "Budget", "Linked expense", "Period",
                     "Status", "Cost centre", "Area" ],
                   rows.first
      assert_equal 4, rows.size, "header + three actuals"

      exp_row = rows.find { |r| r[2] == "Alice Producer" }
      assert_equal %w[2026-05-13 Debit], exp_row.values_at(0, 1)
      assert_equal "123.45", exp_row[3]
      assert_equal "42", exp_row[5]
      assert_equal "03", exp_row[6]
      assert_equal "", exp_row[7].to_s, "an ordinary row has no reconciliation status"

      bud_row = rows.find { |r| r[2] == "Box office" }
      assert_equal "Credit", bud_row[1]
      assert_equal "-500.0", bud_row[3], "income is signed negative so a SUM of the column is net spend"
      assert_equal "Props", bud_row[4]
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
    # The page opens on what is left to do after a reconcile; the whole ledger is one click away.

    test "the index opens on the rows that need attention, and falls back to them on a bad state" do
      sign_in @user

      [ {}, { state: "wibble" } ].each do |params|
        get :index, params: params

        assert_response :success
        assert_equal ::Admin::Reimbursements::ActualsController::STATE_NEEDS_ATTENTION,
                     assigns(:state), params.inspect
        assert_equal [ @unlinked.record_id ], assigns(:actuals).map(&:record_id), params.inspect
      end
      assert_equal 1, assigns(:needs_attention_count)
      assert_equal 3, assigns(:matching_count)
      assert_equal %w[03 04], assigns(:periods)
    end

    # An old bookmark asking for the offsets must still get them (an offset leg never needs attention).
    test "asking for the offsets opens the full ledger with both legs badged and undoable" do
      accrual, = create_offsetting_pair
      sign_in @user

      get :index, params: { include_offsets: "1" }

      assert_equal ::Admin::Reimbursements::ActualsController::STATE_ALL, assigns(:state)
      assert_equal 5, assigns(:actuals).size
      assert_includes response.body, "Offset"
      assert_includes response.body, unoffset_admin_reimbursements_actual_path(accrual.record_id)
      assert_not_includes response.body,
                          new_expense_admin_reimbursements_actual_path(accrual.record_id)
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

    test "searches the narrative and the amount, with the separators a person types stripped" do
      sign_in @user

      { "box off" => @linked_budget, "£123.45" => @linked_expense }.each do |term, row|
        get :index, params: { state: "all", search: term }

        assert_equal [ row.record_id ], assigns(:actuals).map(&:record_id), term
      end
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

    test "the offsetting filter carries through to the CSV export" do
      create_offsetting_pair
      sign_in @user

      get :index, params: { state: "all" }, format: :csv
      assert_equal 4, CSV.parse(response.body).size, "header + the three non-offsetting rows"

      get :index, params: { include_offsets: "1" }, format: :csv
      rows = CSV.parse(response.body, headers: true)
      assert_equal 5, rows.size, "all five rows"
      legs = rows.select { |r| r["Status"] == "Offset" }
      assert_equal 2, legs.size, "an included offset pair is flagged on both legs"
      assert_equal BigDecimal("0"), legs.sum { |r| BigDecimal(r["Amount"]) },
                   "a cross-linked pair contributes nothing to a SUM of the column"
    end

    # --- Undoing an offset --------------------------------------------------

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

    # --- Convert an actual into a From-EUSA expense ------------------------

    test "an unlinked debit row offers a create-expense button" do
      sign_in @user
      get :index

      assert_response :success
      assert_includes response.body, new_expense_admin_reimbursements_actual_path(@unlinked.record_id)
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

    test "new_expense preselects the budget only when the nominal code maps to exactly one" do
      only_budget = create_reimbursements_budget(name: "Venue", nominal_code: "500000")
      sign_in @user

      get :new_expense, params: { id: @unlinked.record_id }
      assert_equal only_budget.record_id, assigns(:form).budget_record_id

      create_reimbursements_budget(name: "Venue B", nominal_code: "500000")
      get :new_expense, params: { id: @unlinked.record_id }
      assert_response :success
      assert_nil assigns(:form).budget_record_id, "the operator picks between them"
    end

    test "a row that cannot become an expense is bounced with the reason" do
      accrual, = create_offsetting_pair
      sign_in @user

      { accrual => /offset/i, @linked_budget => /debit/i,
        @linked_expense => /already/i }.each do |row, reason|
        get :new_expense, params: { id: row.record_id }

        assert_redirected_to admin_reimbursements_actuals_path
        assert_match reason, flash[:alert]
      end
    end

    # Created settled: a From-EUSA expense never enters review or a BACS batch.
    test "create_expense creates a Paid From-EUSA expense dated from the ledger row" do
      sign_in @user

      post :create_expense, params: {
        id: @unlinked.record_id,
        reimbursements_expense_form: { budget_record_id: @budget.record_id,
                                       description: "Room hire recharge",
                                       payment_reference: "J000001234",
                                       amount: "9999.99", expense_type: "Reimbursement" }
      }

      assert_redirected_to admin_reimbursements_actuals_path
      expense = ::Reimbursements::Expense.order(:id).last
      assert_equal ::Reimbursements::Expense::TYPE_FROM_EUSA, expense.expense_type,
                   "the ledger row owns these, not the form"
      assert_equal ::Reimbursements::Status::PAID, expense.status
      assert_equal @unlinked.date, expense.payment_confirmed_date
      # The ledger date, not the click date: lists sort and date claims by it.
      assert_equal @unlinked.date, expense.submitted_at.to_date
      assert_equal BigDecimal("42.0"), expense.amount, "the ledger row owns these, not the form"
      assert_equal BigDecimal("42.0"), expense.amount_excl_vat
      assert_equal "Room hire recharge", expense.description
      assert_equal @budget.record_id, expense.budget_record_id
      assert_nil expense.person, "a cost EUSA levied directly has no payee to reimburse"
      assert_empty expense.receipts
      assert_nil expense.batch_id
      assert_equal expense.id, @unlinked.reload.expense_id
      assert_not_predicate @unlinked, :convertible_to_expense?, "and can't be converted twice"
    end

    # The budget is checked against the list the picker offered, so a deleted or retired line is a
    # form error, not an FK 500 or a quiet charge to a retired budget.
    test "create_expense rejects a missing, deleted or deactivated budget" do
      retired = create_reimbursements_budget(name: "Last year's props", nominal_code: "4900",
                                             active: false)
      sign_in @user

      [ "", "999999", retired.record_id ].each do |budget_id|
        assert_no_difference -> { ::Reimbursements::Expense.count } do
          post :create_expense, params: {
            id: @unlinked.record_id,
            reimbursements_expense_form: { budget_record_id: budget_id, description: "Room hire",
                                           payment_reference: "J000001234" }
          }
        end

        assert_response :unprocessable_entity
        assert assigns(:form).errors[:budget_record_id].present?, budget_id.inspect
      end
      assert_nil @unlinked.reload.expense_id
    end

    # --- Conversion is one unit ---------------------------------------------

    # The convertibility check is re-taken inside the writing transaction: a second click's
    # before_action read predates the first click's commit.
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
      assert_equal @expense.id, @unlinked.reload.expense_id,
                   "the first conversion's link stands"
    end

    # --- Manual link to a claim ---------------------------------------------

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

    test "link_expense offers Pending and Approved claims but no draft or rejected one" do
      claim = lambda do |auto_number, status|
        create_reimbursements_expense(auto_number: auto_number, budget: @budget, status: status,
                                      amount: BigDecimal("42.00"),
                                      amount_excl_vat: BigDecimal("42.00"))
      end
      draft = claim.call(90, ::Reimbursements::Status::DRAFT)
      rejected = claim.call(91, ::Reimbursements::Status::REJECTED)
      pending_claim = claim.call(92, ::Reimbursements::Status::PENDING)
      approved = claim.call(93, ::Reimbursements::Status::APPROVED)
      sign_in @user

      get :link_expense, params: { id: @unlinked.record_id }

      numbers = assigns(:candidates).map(&:auto_number)
      assert_not_includes numbers, draft.auto_number,
                          "a draft is a claim its submitter has not finished writing"
      assert_not_includes numbers, rejected.auto_number,
                          "a rejected claim is one finance refused to pay"
      assert_includes numbers, pending_claim.auto_number
      assert_includes numbers, approved.auto_number
    end

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

    # A claim resolves its centre through its budget, so the list names it: another centre's claim
    # is almost certainly the wrong answer.
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

    # The MARKUP, not the ivar: a bare collection with group_method renders one option per group
    # and offers no budget. Only `as: :grouped_select` really groups.
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
      options = css_select("select#reimbursements_expense_form_budget_record_id optgroup option")
      assert(options.all? { |option| option.text.include?("·") }, "each label prints its nominal code")
      assert_includes groups.last.css("option").map { |option| option["value"] }, @budget.record_id,
                      "an order, not a filter: every other line is still offerable"
      assert_includes css_select("select#reimbursements_expense_form_budget_record_id option")
                      .map { |option| option.text.strip }.join(" "), "Sundries"
    end

    test "confirm_link settles an international claim, links the row and corrects the amount" do
      claim = international_claim
      sign_in @user

      post :confirm_link, params: { id: @unlinked.record_id, expense_id: claim.record_id }

      settled = claim.reload
      assert_equal ::Reimbursements::Status::PAID, settled.status
      assert_equal Date.new(2026, 6, 1), settled.payment_confirmed_date
      assert_equal claim.id, @unlinked.reload[:expense_id]
      assert_equal BigDecimal("42.0"), settled.amount
      assert_match(/corrected to what EUSA charged/, flash[:notice])
    end

    test "confirm_link on a UK claim does not claim a correction" do
      sign_in @user

      post :confirm_link, params: { id: @unlinked.record_id, expense_id: @expense.record_id }

      assert_no_match(/corrected/, flash[:notice])
    end

    test "confirm_link on a vanished claim changes nothing" do
      sign_in @user

      post :confirm_link, params: { id: @unlinked.record_id, expense_id: "999999" }

      assert_match(/no longer exists/, flash[:alert])
      assert_nil @unlinked.reload[:expense_id]
    end

    test "confirm_link refuses a claim the picker never offers, even if it changed since the page loaded" do
      sign_in @user

      ::Admin::Reimbursements::ActualsController::EXCLUDED_LINK_STATUSES.each_with_index do |status, index|
        claim = create_reimbursements_expense(auto_number: 80 + index, budget: @budget, status: status,
                                              amount: BigDecimal("42.00"),
                                              amount_excl_vat: BigDecimal("42.00"))

        post :confirm_link, params: { id: @unlinked.record_id, expense_id: claim.record_id }

        assert_match(/can't settle it/, flash[:alert], status)
        assert_nil @unlinked.reload[:expense_id], status
        assert_equal status, claim.reload.status
      end
    end

    test "confirm_link refuses a row that is already linked" do
      claim = international_claim
      sign_in @user

      post :confirm_link, params: { id: @linked_expense.record_id, expense_id: claim.record_id }

      assert_match(/already linked/, flash[:alert])
      assert_equal ::Reimbursements::Status::SUBMITTED, claim.reload.status
    end

    # --- Unlink -------------------------------------------------------------

    test "unlinking from an income line makes the row splittable again" do
      sign_in @user
      refute @linked_budget.apportionable?, "precondition: a budget-linked credit cannot be split"

      post :unlink, params: { id: @linked_budget.record_id }

      @linked_budget.reload
      assert_nil @linked_budget.budget_id
      assert @linked_budget.apportionable?, "the row it was built for must now offer the split"
      assert @linked_budget.needs_attention?, "unplaced money has to be visible again"
    end

    test "unlinking from a claim sends a claim this row settled back to Submitted" do
      @expense.update!(status: ::Reimbursements::Status::PAID,
                       payment_confirmed_date: Date.new(2026, 5, 13))
      sign_in @user

      post :unlink, params: { id: @linked_expense.record_id }

      @expense.reload
      assert_equal ::Reimbursements::Status::SUBMITTED, @expense.status
      assert_nil @expense.payment_confirmed_date,
                 "a claim reading Submitted must not still carry the date it was paid on"
      assert_nil @linked_expense.reload.expense_id
    end

    test "unlinking leaves a claim that was never settled where it is" do
      sign_in @user
      assert_equal ::Reimbursements::Status::PENDING, @expense.status

      post :unlink, params: { id: @linked_expense.record_id }

      assert_equal ::Reimbursements::Status::PENDING, @expense.reload.status
      assert_nil @linked_expense.reload.expense_id
    end

    # The claim exists only because of the row, so there is no earlier state to return it to.
    test "refuses to unlink a claim that was created from this row" do
      @expense.update!(expense_type: ::Reimbursements::Expense::TYPE_FROM_EUSA,
                       status: ::Reimbursements::Status::PAID)
      sign_in @user

      post :unlink, params: { id: @linked_expense.record_id }

      assert_match(/created FROM this row/, flash[:alert])
      assert_equal @expense.id, @linked_expense.reload.expense_id
      assert_equal ::Reimbursements::Status::PAID, @expense.reload.status
    end

    test "unlinking an already-unlinked row says so and changes nothing" do
      sign_in @user

      post :unlink, params: { id: @unlinked.record_id }

      assert_match(/isn't linked to anything/, flash[:alert])
    end

    test "the ledger offers Unlink on linked rows and not on unlinked ones" do
      sign_in @user

      get :index, params: { state: "all" }

      assert_response :success
      # Prefix match: the button's action carries the page's filters.
      assert_select "form[action^=?]", unlink_admin_reimbursements_actual_path(@linked_expense.record_id)
      assert_select "form[action^=?]", unlink_admin_reimbursements_actual_path(@linked_budget.record_id)
      assert_select "form[action^=?]", unlink_admin_reimbursements_actual_path(@unlinked.record_id), count: 0
    end

    # Additive, not an elsif: a budget-linked debit is still convertible (that reads expense_id).
    test "a budget-linked debit offers Unlink alongside its conversion controls" do
      row = create_reimbursements_actual(nominal_code: "432320", period: "03",
                                         narrative: "Venue recharge", date: Date.new(2026, 5, 15),
                                         debit: BigDecimal("90.0"), budget: @budget)
      sign_in @user

      get :index, params: { state: "all" }

      assert row.convertible_to_expense?, "precondition: the conversion controls are offered"
      assert_select "form[action^=?]", unlink_admin_reimbursements_actual_path(row.record_id)
      assert_select "a[href=?]", new_expense_admin_reimbursements_actual_path(row.record_id)
    end

    # --- Pairing two rows by hand -------------------------------------------

    # The opposite side of @unlinked (a £42 debit on 500000): same figure, code and year.
    def counterpart_for_unlinked(**attrs)
      create_reimbursements_actual(nominal_code: "500000", period: "05", narrative: "Reversal",
                                   date: Date.new(2026, 6, 20), debit: nil,
                                   credit: BigDecimal("42.0"),
                                   financial_year_id: @unlinked.financial_year_id, **attrs)
    end

    test "offers only rows that cancel this one out" do
      match = counterpart_for_unlinked
      wrong_amount = counterpart_for_unlinked(credit: BigDecimal("99.0"))
      wrong_code = counterpart_for_unlinked(nominal_code: "432320")
      linked = counterpart_for_unlinked(expense: @expense)
      same_side = create_reimbursements_actual(nominal_code: "500000", debit: BigDecimal("42.0"),
                                               financial_year_id: @unlinked.financial_year_id)
      sign_in @user

      get :offset_pair, params: { id: @unlinked.record_id }

      assert_response :success
      ids = assigns(:candidates).map(&:record_id)
      assert_includes ids, match.record_id
      refute_includes ids, wrong_amount.record_id, "a different figure cancels nothing"
      refute_includes ids, wrong_code.record_id, "the detector will not pair across nominal codes"
      refute_includes ids, same_side.record_id, "two debits do not cancel out"
      refute_includes ids, linked.record_id, "a linked row would hide spend a claim still counts"
      refute_includes ids, @unlinked.record_id, "a row cannot cancel itself"
    end

    # Two pots' rows stamped as cancelling out leave both pots' rollups short, and re-pasting
    # cannot repair it (dedup skips both legs).
    test "never offers a counterpart from another cost centre" do
      other = create_second_reimbursements_cost_centre
      ours = counterpart_for_unlinked(cost_centre_id: @unlinked.cost_centre_id)
      theirs = counterpart_for_unlinked(cost_centre_id: other.id)
      sign_in @user

      get :offset_pair, params: { id: @unlinked.record_id }

      ids = assigns(:candidates).map(&:record_id)
      assert_includes ids, ours.record_id
      refute_includes ids, theirs.record_id, "two pots' rows never cancel each other out"
    end

    # The picker is a stale read and the link carries no centre, so the gate must hold on the write.
    test "refuses a counterpart from another cost centre or one linked since the page was drawn" do
      other = create_second_reimbursements_cost_centre
      sign_in @user

      [ counterpart_for_unlinked(cost_centre_id: other.id),
        counterpart_for_unlinked.tap { |match| match.update!(expense_id: @expense.id) } ].each do |counterpart|
        post :confirm_offset, params: { id: @unlinked.record_id, counterpart_id: counterpart.record_id }

        assert_match(/can no longer be paired/, flash[:alert])
        refute counterpart.reload.offset?
      end
      refute @unlinked.reload.offset?
    end

    # Rows predating cost centres have none and count as belonging everywhere.
    test "two rows with no cost centre still pair, but not with a placed row" do
      @unlinked.update!(cost_centre_id: nil)
      unplaced = counterpart_for_unlinked(cost_centre_id: nil)
      placed = counterpart_for_unlinked(cost_centre_id: create_second_reimbursements_cost_centre.id)
      sign_in @user

      get :offset_pair, params: { id: @unlinked.record_id }

      ids = assigns(:candidates).map(&:record_id)
      assert_includes ids, unplaced.record_id
      refute_includes ids, placed.record_id
    end

    test "pairing two rows stamps and cross-links both" do
      match = counterpart_for_unlinked
      sign_in @user

      post :confirm_offset, params: { id: @unlinked.record_id, counterpart_id: match.record_id }

      assert @unlinked.reload.offset?
      assert match.reload.offset?
      assert_equal match.id, @unlinked.offset_of_id
      assert_equal @unlinked.id, match.offset_of_id
    end

    test "refuses to pair a row that is already linked, naming the fix" do
      sign_in @user

      get :offset_pair, params: { id: @linked_expense.record_id }

      assert_match(/Unlink it first/, flash[:alert])
    end

    test "the ledger offers Mark as offsetting only on rows needing attention" do
      sign_in @user

      get :index, params: { state: "all" }

      assert_select "a[href=?]", offset_pair_admin_reimbursements_actual_path(@unlinked.record_id)
      assert_select "a[href=?]",
                    offset_pair_admin_reimbursements_actual_path(@linked_expense.record_id), count: 0
    end
  end
  end
end
