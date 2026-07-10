require "test_helper"

module Admin
  module Reimbursements
    class ReviewControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers
      include ActiveJob::TestHelper

      MC = ::Reimbursements::ModulusCheck
      EXP = FIELD_IDS[:expenses]

      # Modulus verdict keyed by account number, so tests don't depend on the
      # gitignored Pay.UK rule files.
      class FakeChecker
        def initialize(by_account = {})
          @by_account = by_account
        end

        def check(_sort_code, account_number)
          @by_account.fetch(account_number, MC::OUTSIDE_SPEC)
        end
      end

      setup do
        Role.create!(name: "Business Manager")
             .permissions << Permission.create(action: "manage", subject_class: "reimbursements_finance")
        users(:member).add_role("Business Manager")
        @user = users(:member)

        @person = airtable_person_record(id: "recPer1", name: "Pat Producer", email: "pat@example.com",
                                         sort_code: "08-99-99", account_number: "66374958")
        @no_bank_person = airtable_person_record(id: "recPer2", name: "Nora NoBank",
                                                 email: "nora@example.com")
        @budget = airtable_budget_record(id: "recBud1", name: "Props", nominal_code: "4000")

        @checker = FakeChecker.new("66374958" => MC::VALID)
        ReviewController.checker_builder = -> { @checker }
      end

      teardown do
        BaseController.store_builder = -> { ::Reimbursements::Store.new }
        ReviewController.checker_builder = -> { MC.default_checker }
      end

      def pending_expense(id:, **attrs)
        airtable_expense_record(id: id, payee_id: attrs.delete(:payee_id) || "recPer1",
                                budget_id: attrs.delete(:budget_id) || "recBud1",
                                status: "Pending", **attrs)
      end

      def rebuild_store(expenses:, people: nil, budgets: nil)
        @store, @client = build_fake_store(
          expenses: expenses,
          people: people || [ @person, @no_bank_person ],
          budgets: budgets || [ @budget ]
        )
        BaseController.store_builder = -> { @store }
      end

      # --- Auth gating -----------------------------------------------------

      test "requires sign-in" do
        rebuild_store(expenses: [])
        get :index
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        rebuild_store(expenses: [])
        sign_in users(:committee)
        get :index
        assert_response :forbidden
      end

      test "the producer portal permission alone does not grant finance access" do
        producer = Role.create!(name: "Producer")
        producer.permissions << Permission.create(action: "access", subject_class: "reimbursements")
        other = users(:member_with_phone_number)
        other.add_role("Producer")
        rebuild_store(expenses: [])
        sign_in other

        get :index

        assert_response :forbidden
      end

      # --- Index: partition, flags, AI kick --------------------------------

      test "partitions pending into ready and needs-attention, and lists approved separately" do
        ready = pending_expense(id: "recReady", payment_reference: "PROPS PAT")
        attention = pending_expense(id: "recAttn", amount_excl_vat: nil) # missing excl VAT
        approved = pending_expense(id: "recAppr").tap { |r| r["fields"][EXP[:status]] = "Approved" }
        rebuild_store(expenses: [ ready, attention, approved ])
        sign_in @user

        get :index

        assert_response :success
        assert_equal %w[recReady], assigns(:ready).map(&:record_id)
        assert_equal %w[recAttn], assigns(:attention).map(&:record_id)
        assert_equal %w[recAppr], assigns(:approved).map(&:record_id)
      end

      test "renders the payee-override warning" do
        overridden = pending_expense(id: "recOvr", payment_reference: "PROPS PAT", overrides: {
          EXP[:payee_name_override] => "Acme Lighting Ltd",
          EXP[:sort_code_override] => "20-00-00",
          EXP[:account_number_override] => "66374958"
        })
        rebuild_store(expenses: [ overridden ])
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "Direct payment to"
        assert_includes response.body, "Acme Lighting Ltd"
      end

      test "renders a duplicate-submission warning" do
        first = pending_expense(id: "recDupA", amount: 12.5, payment_reference: "PROPS PAT")
        second = pending_expense(id: "recDupB", amount: 12.5, payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ first, second ])
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "Possible duplicate of"
      end

      test "kicks an AI check for each unchecked pending expense only" do
        unchecked = pending_expense(id: "recNew", payment_reference: "PROPS PAT")
        checked = pending_expense(id: "recDone", payment_reference: "PROPS PAT",
                                  overrides: { EXP[:ai_check_status] => "pass" })
        rebuild_store(expenses: [ unchecked, checked ])
        sign_in @user

        assert_enqueued_with(job: ::Reimbursements::AiCheckJob, args: [ "recNew" ]) do
          get :index
        end
        assert_enqueued_jobs 1, only: ::Reimbursements::AiCheckJob
      end

      # --- Save ------------------------------------------------------------

      test "save writes the edited fields" do
        expense = pending_expense(id: "recEdit", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :save, params: { id: "recEdit", amount: "20.00", amount_excl_vat: "16.67",
                               description: "Updated blood", payment_reference: "NEWREF",
                               nominal_code_override: "4100", budget_record_id: "recBud1" }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        _table, record_id, fields = @client.updated.sole
        assert_equal "recEdit", record_id
        assert_equal 20.0, fields[EXP[:amount]]
        assert_equal 16.67, fields[EXP[:amount_excl_vat]]
        assert_equal "Updated blood", fields[EXP[:description]]
        assert_equal "NEWREF", fields[EXP[:payment_reference]]
        assert_equal "4100", fields[EXP[:nominal_code_override]]
      end

      test "save leaves excl VAT untouched when zero is submitted" do
        expense = pending_expense(id: "recEdit", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :save, params: { id: "recEdit", amount: "20.00", amount_excl_vat: "0",
                               description: "x", payment_reference: "y", budget_record_id: "recBud1" }

        _table, _id, fields = @client.updated.sole
        assert_not fields.key?(EXP[:amount_excl_vat])
      end

      # --- Approve ---------------------------------------------------------

      test "approve auto-fills a payment reference when blank and marks approved" do
        expense = pending_expense(id: "recApprove", payment_reference: "")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :approve, params: { id: "recApprove" }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        _table, _id, fields = @client.updated.sole
        assert_equal "Approved", fields[EXP[:status]]
        assert_equal "Props", fields[EXP[:payment_reference]]
      end

      test "approve keeps an existing payment reference" do
        expense = pending_expense(id: "recApprove", payment_reference: "KEEPME")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :approve, params: { id: "recApprove" }

        _table, _id, fields = @client.updated.sole
        assert_equal "Approved", fields[EXP[:status]]
        assert_not fields.key?(EXP[:payment_reference])
      end

      test "approve is blocked without effective bank details" do
        expense = pending_expense(id: "recNoBank", payee_id: "recPer2", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :approve, params: { id: "recNoBank" }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/without bank details/, flash[:alert])
        assert_empty @client.updated
      end

      # --- Reject ----------------------------------------------------------

      test "reject requires a reason" do
        expense = pending_expense(id: "recRej", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :reject, params: { id: "recRej", rejection_reason: "  " }

        assert_match(/reason is required/, flash[:alert])
        assert_empty @client.updated
        assert_enqueued_emails 0
      end

      test "reject stamps the reason and notified time and queues the rejection email" do
        expense = pending_expense(id: "recRej", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        assert_enqueued_emails 1 do
          patch :reject, params: { id: "recRej", rejection_reason: "Missing receipt" }
        end

        _table, _id, fields = @client.updated.sole
        assert_equal "Rejected", fields[EXP[:status]]
        assert_equal "Missing receipt", fields[EXP[:rejection_reason]]
        assert fields[EXP[:rejection_notified]].present?
      end

      test "reject without a payee email still rejects but does not stamp notified or email" do
        expense = pending_expense(id: "recRej", payee_id: "recPer2", payment_reference: "PROPS PAT")
        # recPer2 (Nora) has no email
        @person2_no_email = airtable_person_record(id: "recPer2", name: "Nora NoBank", email: "")
        rebuild_store(expenses: [ expense ], people: [ @person, @person2_no_email ])
        sign_in @user

        patch :reject, params: { id: "recRej", rejection_reason: "Bad" }

        _table, _id, fields = @client.updated.sole
        assert_equal "Rejected", fields[EXP[:status]]
        assert_not fields.key?(EXP[:rejection_notified])
        assert_enqueued_emails 0
      end

      test "acting on an unknown expense 404s" do
        rebuild_store(expenses: [])
        sign_in @user

        patch :approve, params: { id: "recNope" }

        assert_response :not_found
      end
    end
  end
end
