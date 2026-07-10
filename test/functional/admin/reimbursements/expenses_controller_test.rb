require "test_helper"

module Admin
  module Reimbursements
  class ExpensesControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    setup do
      grant_member_role_reimbursements_access
      @user = users(:member)
      @store, @client = build_fake_store(
        expenses: [ airtable_expense_record, airtable_expense_record(id: "recExp2", payee_id: "recPerOther", description: "Someone else's") ],
        people: [ airtable_person_record(email: @user.email), airtable_person_record(id: "recPerOther", email: "other@example.com") ],
        budgets: [ airtable_budget_record ]
      )
      BaseController.store_builder = -> { @store }
    end

    teardown do
      BaseController.store_builder = -> { ::Reimbursements::Store.new }
      BaseController.extractor_builder = -> { ::Reimbursements::Extractor.new }
    end

    # A dedicated role, so users holding only member/committee stay denied.
    def grant_member_role_reimbursements_access
      producer = Role.create!(name: "Producer")
      producer.permissions << Permission.create(action: "access", subject_class: "reimbursements")
      users(:member).add_role("Producer")
      users(:member_with_phone_number).add_role("Producer")
    end

    test "requires sign-in" do
      get :index
      assert_redirected_to new_user_session_path
    end

    test "denies members without the reimbursements permission" do
      sign_in users(:committee)

      get :index

      assert_response :forbidden
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
      assert_redirected_to admin_reimbursements_expenses_path

      get :index
      assert_equal 2, @client.list_calls[:expenses]
    end

    test "prompts for payment details when bank details are missing" do
      sign_in @user

      get :index

      assert_includes response.body, "add your payment details"
    end

    test "shows an empty state for users with no expenses" do
      other = users(:member_with_phone_number)
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

      assert_redirected_to admin_reimbursements_expenses_path
      table, fields = @client.created.sole
      assert_equal :expenses, table
      f = ReimbursementsTestHelpers::FIELD_IDS[:expenses]
      assert_equal "Pending", fields[f[:status]]
      assert_equal [ "recPer1" ], fields[f[:payee]]
      assert_equal [ "recBud1" ], fields[f[:budget]]
      assert_in_delta 12.5, fields[f[:amount]]
      assert_equal 1, @client.uploads.size
    end

    test "create as draft accepts gaps and writes Draft status" do
      sign_in @user

      post :create, params: { reimbursements_expense_form: {
        save_as_draft: "1", description: "Half-finished", receipts: [ receipt_upload ]
      } }

      assert_redirected_to admin_reimbursements_expenses_path
      _table, fields = @client.created.sole
      assert_equal "Draft", fields[ReimbursementsTestHelpers::FIELD_IDS[:expenses][:status]]
    end

    test "create degrades to a flash when the receipt upload fails" do
      sign_in @user
      @client.fail_uploads = true

      post :create, params: { reimbursements_expense_form: valid_form_params }

      assert_equal 1, @client.created.size
      assert_redirected_to edit_admin_reimbursements_expense_path("recNew1")
      assert_match(/uploading the receipt failed/, flash[:alert])
    end

    test "extract rejects unusable files without calling gemini" do
      sign_in @user
      BaseController.extractor_builder = -> { raise "extractor must not be built" }

      post :extract, params: { receipts: [ fixture_file_upload("reimbursements_receipt.pdf", "application/zip") ] }

      assert_response :success
      assert_not response.parsed_body["ok"]
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
      assert_redirected_to admin_reimbursements_expenses_path
      assert_equal 1, @client.created.size
    end

    test "extract returns the extraction as json" do
      sign_in @user
      extraction = ::Reimbursements::Extractor::Extraction.new(
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
      BaseController.extractor_builder = -> { FakeExtractor.new(::Reimbursements::Extractor::Extraction.new(error: "no key")) }

      post :extract, params: { receipts: [ receipt_upload ] }

      assert_response :success
      assert_not response.parsed_body["ok"]
    end

    test "edit refetches once when the cached list is stale (email-in link)" do
      sign_in @user
      get :index # warms the expense cache without the email-in expense

      @client.list_records(:expenses) << airtable_expense_record(id: "recExpMail", description: "Emailed taxi receipt")

      get :edit, params: { id: "recExpMail" }

      assert_response :success
      assert_includes response.body, "Emailed taxi receipt"
    end

    test "edit renders the prefilled form for an own pending expense" do
      sign_in @user

      get :edit, params: { id: "recExp1" }

      assert_response :success
      assert_includes response.body, "Fake blood"
      assert_includes response.body, "receipt.pdf"
    end

    test "edit 404s for another person's expense" do
      sign_in @user

      get :edit, params: { id: "recExp2" }

      assert_response :not_found
    end

    test "edit 404s for a non-pending expense" do
      approved = airtable_expense_record(id: "recExp3", status: "Approved")
      @store, @client = build_fake_store(
        expenses: [ approved ],
        people: [ airtable_person_record(email: @user.email) ],
        budgets: [ airtable_budget_record ]
      )
      BaseController.store_builder = -> { @store }
      sign_in @user

      get :edit, params: { id: "recExp3" }

      assert_response :not_found
    end

    test "update writes changed fields without requiring a new receipt" do
      sign_in @user

      patch :update, params: { id: "recExp1",
                               reimbursements_expense_form: valid_form_params.except(:receipts).merge(description: "Even more fake blood") }

      assert_redirected_to admin_reimbursements_expenses_path
      _table, record_id, fields = @client.updated.sole
      assert_equal "recExp1", record_id
      assert_equal "Even more fake blood",
                   fields[ReimbursementsTestHelpers::FIELD_IDS[:expenses][:description]]
      assert_equal "Pending", fields[ReimbursementsTestHelpers::FIELD_IDS[:expenses][:status]],
                   "a full (non-draft) save submits the expense"
      assert_empty @client.uploads
    end

    test "submitting a receipt-less draft demands a receipt" do
      bare_draft = airtable_expense_record(id: "recDraft", status: "Draft", receipts: nil)
      bare_draft["fields"].delete(ReimbursementsTestHelpers::FIELD_IDS[:expenses][:receipt])
      @store, @client = build_fake_store(
        expenses: [ bare_draft ],
        people: [ airtable_person_record(email: @user.email) ],
        budgets: [ airtable_budget_record ]
      )
      BaseController.store_builder = -> { @store }
      sign_in @user

      patch :update, params: { id: "recDraft",
                               reimbursements_expense_form: valid_form_params.except(:receipts) }
      assert_response :unprocessable_entity
      assert_empty @client.updated

      patch :update, params: { id: "recDraft", reimbursements_expense_form: valid_form_params }
      assert_redirected_to admin_reimbursements_expenses_path
      assert_equal 1, @client.uploads.size
    end

    test "update rejects invalid input without writing" do
      sign_in @user

      patch :update, params: { id: "recExp1",
                               reimbursements_expense_form: valid_form_params.except(:receipts).merge(amount: "") }

      assert_response :unprocessable_entity
      assert_empty @client.updated
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
end
