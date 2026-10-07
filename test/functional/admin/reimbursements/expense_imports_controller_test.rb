require "test_helper"
require_relative "../../../support/expense_import_sheet_helpers"

module Admin
  module Reimbursements
    class ExpenseImportsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers
      include ExpenseImportSheetHelpers

      FY = ::Reimbursements::FinancialYear
      IMPORT = ::Reimbursements::ExpenseImport
      STATUS = ::Reimbursements::Status

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)
        @year = FY.create!(label: "Fringe 2027", active: true)
        @cost_centre = ::Reimbursements::CostCentre.default
        @payee = create_reimbursements_person(name: "Alice Producer", email: "alice@example.com")
        @budget = create_reimbursements_budget(name: "Props", cost_centre: @cost_centre,
                                               financial_year: @year)
      end

      def row(**) = expense_import_row(**)

      def tsv(*) = expense_import_sheet(*)

      def import_params(text, **extra)
        { year: @year.key, cost_centre_id: @cost_centre.id, pasted_text: text }.merge(extra)
      end

      # --- Step 1: the form --------------------------------------------------

      test "show renders the paste/upload form" do
        sign_in @user

        get :show

        assert_response :success
        assert_equal @year, assigns(:selected_financial_year)
      end

      test "show preselects the cost centre a link named" do
        centre = create_second_reimbursements_cost_centre
        sign_in @user

        get :show, params: { cost_centre_id: centre.id }

        assert_equal centre, assigns(:selected_cost_centre)
      end

      test "show says so when no financial year is set up at all" do
        @budget.update!(financial_year: nil)
        FY.delete_all
        sign_in @user

        get :show

        assert_response :success
        assert_match(/No financial year is set up yet/, response.body)
      end

      # Turbo Drive discards a non-redirect response to a form POST, so the wizard
      # lives in one Turbo Frame.
      test "every wizard step renders inside the turbo frame" do
        sign_in @user

        get :show
        assert_match(/turbo-frame id="expense_import"/, response.body)

        post :preview, params: import_params(tsv(row))
        assert_match(/turbo-frame id="expense_import"/, response.body)

        post :apply, params: import_params(tsv(row))
        assert_match(/turbo-frame id="expense_import"/, response.body)
      end

      test "the template download names every column the importer reads" do
        sign_in @user

        get :template, params: { format: :csv }

        assert_response :success
        assert_match(/filename="expense-import-template\.csv"/, response.headers["Content-Disposition"])
        header, hints = CSV.parse(response.body)
        assert_equal IMPORT::TSV_HEADERS, header
        assert_equal IMPORT::TEMPLATE_HINTS, hints
        assert_match(/Invoice/, hints[header.index("Type")])
      end

      # --- Step 2: preview ---------------------------------------------------

      test "preview buckets the pasted sheet without writing anything" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::Expense.count } do
          post :preview, params: import_params(tsv(row(reference: "OLD-1"),
                                                   row(reference: "OLD-2", status: STATUS::APPROVED)))
        end

        assert_response :success
        assert_equal 2, assigns(:import).entries_in(:create).size
        assert_includes response.body, "EUSA pays it again"
      end

      test "preview states the column it read for each field and the ones it did not find" do
        sign_in @user

        post :preview, params: import_params(
          "Claim ID\tStatus\tPayee email\tBudget\tAmount\tPayment reference\n" \
          "2019-014\tPaid\talice@example.com\tProps\t120\tPROPS ALICE"
        )

        assert_select "details td span.font-mono", text: "Claim ID"
        assert_includes response.body, "not in this sheet"
      end

      test "preview offers to register a submitter nobody has, never one two people share" do
        2.times { |i| create_reimbursements_person(name: "Sam Jones", email: "sam#{i}@example.com") }
        sign_in @user

        post :preview, params: import_params(tsv(row(payee_email: "nobody@example.com")))
        assert_select "a[href=?]", new_admin_reimbursements_person_path,
                      text: "Register them on the People screen"

        post :preview, params: import_params(tsv(row(payee_email: "", submitter_name: "Sam Jones")))
        assert_includes response.body, "more than one person"
        assert_select "a", text: "Register them on the People screen", count: 0
      end

      test "preview names the only cost centre in its heading when none was picked" do
        sign_in @user

        post :preview, params: import_params(tsv(row), cost_centre_id: "")

        assert_includes response.body, "Preview: Fringe 2027 · #{@cost_centre.name}"
      end

      test "preview refuses an empty paste" do
        sign_in @user

        post :preview, params: import_params("   ")

        assert_response :success
        assert_includes response.body, ExpenseImportsController::NOTHING_PASTED_ALERT
        assert_nil assigns(:import)
      end

      # --- Step 3: apply -----------------------------------------------------

      test "apply creates the claims" do
        sign_in @user

        assert_difference -> { ::Reimbursements::Expense.count }, 2 do
          post :apply, params: import_params(tsv(row(reference: "OLD-1"),
                                                 row(reference: "OLD-2")))
        end

        assert_response :success
        claim = ::Reimbursements::Expense.find_by(import_key: "OLD-1")
        assert_equal STATUS::PAID, claim.status
        assert_equal BigDecimal("120"), claim.amount
        assert_equal @payee, claim.person
        assert_equal @budget, claim.budget
        assert_equal @year, claim.financial_year
      end

      test "apply writes nothing when one row is unreadable, and shows the preview again" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::Expense.count } do
          post :apply, params: import_params(tsv(row(reference: "OLD-1"),
                                                 row(reference: "OLD-2", amount: "about a ton")))
        end

        assert_response :unprocessable_entity
        assert_match(/about a ton/, response.body)
        assert_match(/1 line can.t be imported/, response.body)
        assert_select "input[type=submit][disabled]"
      end

      test "apply refuses a paste that never reached the preview" do
        sign_in @user

        post :apply, params: { year: @year.key, cost_centre_id: @cost_centre.id }

        assert_redirected_to admin_reimbursements_expense_import_path(year: @year.key,
                                                                      cost_centre: @cost_centre.key)
      end

      # --- Double-apply safety -----------------------------------------------

      test "applying the same sheet twice creates nothing the second time" do
        sign_in @user

        post :apply, params: import_params(tsv(row))
        assert_equal 1, ::Reimbursements::Expense.count

        post :apply, params: import_params(tsv(row))

        assert_response :success
        assert_equal 1, ::Reimbursements::Expense.count
        assert_equal 1, assigns(:import).entries_in(:already_imported).size

        post :preview, params: import_params(tsv(row))

        assert_includes response.body, "has been imported before"
        assert_select "input[type=submit][value='Nothing to import'][disabled]"
      end

      # --- An import must not email anyone -----------------------------------
      # Every producer email comes from BatchProcessor, the nightly reminders or an
      # explicit reject; an import must reach none of them.

      test "apply sends no mail and enqueues no job" do
        sign_in @user
        notifier = FakeNotifier.new
        ::Admin::Reimbursements::BaseController.notifier_builder = ->(cost_centre:) { notifier }

        assert_no_enqueued_jobs do
          assert_no_emails do
            post :apply, params: import_params(tsv(row(reference: "OLD-1", status: STATUS::PENDING),
                                                   row(reference: "OLD-2", status: STATUS::APPROVED)))
          end
        end

        assert_empty notifier.calls
      ensure
        ::Admin::Reimbursements::BaseController.notifier_builder =
          ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre) }
      end

      # --- The cost centre has to be chosen ----------------------------------
      # A whole sheet of claims in the wrong pot is a large quiet mistake, so the
      # first centre is never preselected.

      test "apply accepts a blank cost centre while only one is configured" do
        sign_in @user

        assert_difference -> { ::Reimbursements::Expense.count }, 1 do
          post :apply, params: import_params(tsv(row), cost_centre_id: "")
        end
      end

      test "apply refuses without a cost centre once there are two to choose from" do
        create_second_reimbursements_cost_centre
        sign_in @user

        assert_no_difference -> { ::Reimbursements::Expense.count } do
          post :apply, params: import_params(tsv(row), cost_centre_id: "")
        end

        assert_response :unprocessable_entity
        assert_includes response.body, "Choose which cost centre"
      end

      test "preview refuses without a cost centre and keeps the paste" do
        create_second_reimbursements_cost_centre
        sign_in @user

        post :preview, params: import_params(tsv(row), cost_centre_id: "")

        assert_response :unprocessable_entity
        assert_includes response.body, "Choose which cost centre"
        assert_includes response.body, "Fake blood"
      end

      test "the cost-centre select offers a prompt rather than preselecting the first" do
        create_second_reimbursements_cost_centre
        sign_in @user

        get :show

        assert_response :success
        assert_includes response.body, "Choose a cost centre…"
        assert_select "select#cost_centre_id option[selected]", 0
      end

      # --- What the screen says is required --------------------------------
      # Columns the sheet must CARRY and cells every row must FILL are separate requirements.

      test "the template hints do not call a row-required column optional" do
        IMPORT::REQUIRED_CELL_FIELDS.each do |field|
          hint = IMPORT::FIELDS.fetch(field)[:hint].to_s
          refute_match(/optional/i, hint,
                       "#{IMPORT::FIELDS.fetch(field)[:label]}'s template hint says optional")
        end
      end

      test "the intro states both requirements separately" do
        sign_in @user

        get :show

        assert_match(/sheet must carry/i, response.body)
        assert_match(/every row must fill/i, response.body)
        assert_match(/Payment reference/, response.body)
      end
    end
  end
end
