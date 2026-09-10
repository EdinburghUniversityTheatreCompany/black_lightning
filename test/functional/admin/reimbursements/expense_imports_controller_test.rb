require "test_helper"

module Admin
  module Reimbursements
    class ExpenseImportsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      FY = ::Reimbursements::FinancialYear
      IMPORT = ::Reimbursements::ExpenseImport
      STATUS = ::Reimbursements::Status
      HEADERS = IMPORT::TSV_HEADERS.join("\t").freeze

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)
        @year = FY.create!(label: "Fringe 2027", active: true)
        @cost_centre = ::Reimbursements::CostCentre.default
        @payee = create_reimbursements_person(name: "Alice Producer", email: "alice@example.com")
        @budget = create_reimbursements_budget(name: "Props", cost_centre: @cost_centre,
                                               financial_year: @year)
      end

      def row(reference: "OLD-1", status: STATUS::PAID, payee: "alice@example.com",
              budget: "Props", amount: "120.00", excl_vat: "100.00", description: "Fake blood",
              payment_reference: "PROPS ALICE", type: "", number: "", submitted: "", paid: "")
        [ reference, status, payee, budget, amount, excl_vat, description, payment_reference,
          type, number, submitted, paid, "", "", "" ].join("\t")
      end

      def tsv(*rows) = ([ HEADERS ] + rows).join("\n")

      def import_params(text, **extra)
        { year: @year.key, cost_centre_id: @cost_centre.id, pasted_text: text }.merge(extra)
      end

      # --- Auth gating -------------------------------------------------------

      test "requires sign-in" do
        get :show

        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        grant_producer_permission(users(:committee))
        sign_in users(:committee)

        get :show

        assert_response :forbidden
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

      # Turbo Drive rejects a non-redirect response to a form POST and discards
      # it, so a stateless wizard has to live in one Turbo Frame — the same
      # reason the budget import and Reconcile do.
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
        assert_includes response.body, "Reference"
        assert_includes response.body, "Status"
      end

      # --- Step 2: preview ---------------------------------------------------

      test "preview buckets the pasted sheet without writing anything" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::Expense.count } do
          post :preview, params: import_params(tsv(row(reference: "OLD-1"),
                                                   row(reference: "OLD-2")))
        end

        assert_response :success
        assert_equal 2, assigns(:import).entries_in(:create).size
      end

      test "preview refuses an empty paste" do
        sign_in @user

        post :preview, params: import_params("   ")

        assert_response :success
        assert_match(/paste|upload/i, response.body)
        assert_nil assigns(:import)
      end

      test "preview points an unknown payee at the register-a-person form" do
        sign_in @user

        post :preview, params: import_params(tsv(row(payee: "nobody@example.com")))

        # The preview always renders: it is a report on the sheet, not a
        # submission. Only apply refuses.
        assert_response :success
        assert_includes response.body, new_admin_reimbursements_person_path
      end

      test "preview carries the sheet on as TSV in a hidden field" do
        sign_in @user

        post :preview, params: import_params(tsv(row))

        assert_match(/name="pasted_text".*OLD-1/m, response.body)
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
      end

      test "apply refuses without a cost centre" do
        create_second_reimbursements_cost_centre
        sign_in @user

        assert_no_difference -> { ::Reimbursements::Expense.count } do
          post :apply, params: import_params(tsv(row), cost_centre_id: "")
        end

        assert_response :unprocessable_entity
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
      end

      # --- An import must not email anyone -----------------------------------
      #
      # Every producer email in this portal is sent by BatchProcessor, the
      # nightly reminders or an explicit reject. Thirty historical claims
      # landing at once must reach none of them.

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

      test "an imported claim is not marked as having notified its producer" do
        sign_in @user

        post :apply, params: import_params(tsv(row(status: STATUS::PAID)))

        claim = ::Reimbursements::Expense.sole
        assert_not claim.producer_notified
        assert_nil claim.rejection_notified
      end
    end
  end
end
