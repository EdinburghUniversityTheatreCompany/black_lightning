require "test_helper"

module Reimbursements
  class ExpensesControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    setup do
      @user = users(:user)
      @store, @client = build_fake_store(
        expenses: [ airtable_expense_record, airtable_expense_record(id: "recExp2", payee_id: "recPerOther", description: "Someone else's") ],
        people: [ airtable_person_record(email: @user.email), airtable_person_record(id: "recPerOther", email: "other@example.com") ],
        budgets: [ airtable_budget_record ]
      )
      BaseController.store_builder = -> { @store }
    end

    teardown do
      BaseController.store_builder = -> { Store.new }
      BaseController.extractor_builder = -> { Extractor.new }
    end

    test "requires sign-in" do
      get :index
      assert_redirected_to new_user_session_path
    end

    test "shows only the current user's expenses" do
      sign_in @user

      get :index

      assert_response :success
      assert_equal [ "recExp1" ], assigns(:expenses).map(&:record_id)
      assert_includes response.body, "Fake blood"
      assert_not_includes response.body, "Someone else&#39;s"
    end

    test "links the user to their airtable person by email on first visit" do
      sign_in @user
      assert_nil @user.airtable_person_id

      get :index

      assert_equal "recPer1", @user.reload.airtable_person_id
    end

    test "refresh busts the cache and redirects to a clean url" do
      sign_in @user

      get :index
      assert_equal 1, @client.list_calls[:expenses]

      get :index, params: { refresh: 1 }
      assert_redirected_to reimbursements_expenses_path

      get :index
      assert_equal 2, @client.list_calls[:expenses]
    end

    test "prompts for payment details when bank details are missing" do
      sign_in @user

      get :index

      assert_includes response.body, "add your payment details"
    end

    test "shows an empty state for users with no expenses" do
      other = users(:member)
      sign_in other

      get :index

      assert_response :success
      assert_includes response.body, "No expenses yet"
    end

    def receipt_upload
      fixture_file_upload("reimbursements_receipt.pdf", "application/pdf")
    end

    def valid_form_params
      {
        expense_type: "Reimbursement", amount: "12.50", amount_excl_vat: "10.42",
        budget_record_id: "recBud1", description: "Fake blood",
        payment_reference: "PROPS PAT", vat_itemised: "true",
        receipts: [ receipt_upload ]
      }
    end

    test "new renders the receipt-first form" do
      sign_in @user

      get :new

      assert_response :success
      assert_includes response.body, "reimbursements-receipt"
      assert_includes response.body, "Props"
    end

    test "create writes a pending expense with receipts and redirects" do
      sign_in @user

      post :create, params: { reimbursements_expense_form: valid_form_params }

      assert_redirected_to reimbursements_expenses_path
      table, fields = @client.created.sole
      assert_equal :expenses, table
      f = ReimbursementsTestHelpers::FIELD_IDS[:expenses]
      assert_equal "Pending", fields[f[:status]]
      assert_equal [ "recPer1" ], fields[f[:payee]]
      assert_equal [ "recBud1" ], fields[f[:budget]]
      assert_in_delta 12.5, fields[f[:amount]]
      assert_equal 1, @client.uploads.size
    end

    test "create without a receipt re-renders and writes nothing" do
      sign_in @user

      post :create, params: { reimbursements_expense_form: valid_form_params.except(:receipts) }

      assert_response :unprocessable_entity
      assert_empty @client.created
    end

    test "create without vat acknowledgement soft-blocks when vat not itemised" do
      sign_in @user
      params = valid_form_params.merge(vat_itemised: "false", amount_excl_vat: "12.50")

      post :create, params: { reimbursements_expense_form: params }
      assert_response :unprocessable_entity
      assert_empty @client.created

      post :create, params: { reimbursements_expense_form: params.merge(vat_acknowledged: "1", receipts: [ receipt_upload ]) }
      assert_redirected_to reimbursements_expenses_path
      assert_equal 1, @client.created.size
    end

    test "extract returns the extraction as json" do
      sign_in @user
      extraction = Extractor::Extraction.new(
        merchant: "EBS", total_amount: BigDecimal("12.5"), vat_amount: BigDecimal("2.08"),
        vat_itemised: true, suggested_description: "Props",
        suggested_budget_record_id: "recBud1", suggested_payment_reference: "PROPS"
      )
      BaseController.extractor_builder = -> { FakeExtractor.new(extraction) }

      post :extract, params: { receipts: [ receipt_upload ] }

      assert_response :success
      body = response.parsed_body
      assert body["ok"]
      assert_equal "12.5", body["total_amount"]
      assert_equal "10.42", body["amount_excl_vat"]
      assert_equal "recBud1", body["suggested_budget_record_id"]
    end

    test "extract reports failure as ok false" do
      sign_in @user
      BaseController.extractor_builder = -> { FakeExtractor.new(Extractor::Extraction.new(error: "no key")) }

      post :extract, params: { receipts: [ receipt_upload ] }

      assert_response :success
      assert_not response.parsed_body["ok"]
    end

    # Returns a canned extraction regardless of input.
    class FakeExtractor
      def initialize(extraction)
        @extraction = extraction
      end

      def extract(**)
        @extraction
      end
    end
  end
end
