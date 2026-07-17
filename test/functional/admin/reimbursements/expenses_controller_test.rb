require "test_helper"

module Admin
  module Reimbursements
  class ExpensesControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    setup do
      grant_member_role_reimbursements_access
      @user = users(:member)
      @person = create_reimbursements_person(email: @user.email)
      @other_person = create_reimbursements_person(name: "Other Person", email: "other@example.com")
      @budget = create_reimbursements_budget
      @expense = create_reimbursements_expense(person: @person, budget: @budget)
      @other_expense = create_reimbursements_expense(person: @other_person, budget: @budget,
                                                     description: "Someone else's")
    end

    teardown do
      BaseController.store_builder = -> { ::Reimbursements.build_store }
      BaseController.extractor_builder = -> { ::Reimbursements::Extractor.new }
    end

    # A dedicated role, so users holding only member/committee stay denied.
    def grant_member_role_reimbursements_access
      producer = Role.create!(name: "Producer")
      producer.permissions << Permission.create(action: "access", subject_class: "reimbursements")
      users(:member).add_role("Producer")
      users(:member_with_phone_number).add_role("Producer")
    end

    # Airtable-era cache behaviour (production runs the Airtable backend until
    # the flip): inject the fake Airtable store. PersonLink on the database
    # backend can only remember an AR person, so the user is pre-linked and the
    # fake person reuses the DB person's numeric id as its Airtable record id
    # (the FK needs a real row).
    def use_fake_airtable_store
      @user.update_column(:reimbursements_person_id, @person.id)
      @store, @client = build_fake_store(
        expenses: [ airtable_expense_record(payee_id: @person.record_id) ],
        people: [ airtable_person_record(id: @person.record_id, email: @user.email) ],
        budgets: [ airtable_budget_record ]
      )
      BaseController.store_builder = -> { @store }
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
      assert_equal [ @expense.record_id ], assigns(:expenses).map(&:record_id)
      assert_includes response.body, "Fake blood"
      assert_not_includes response.body, "Someone else&#39;s"
    end

    test "links the user to their payee record by email on first visit" do
      sign_in @user
      assert_nil @user.reimbursements_person_id

      get :index

      assert_equal @person.id, @user.reload.reimbursements_person_id
    end

    test "refresh busts the airtable cache and redirects to a clean url" do
      use_fake_airtable_store
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
        budget_record_id: @budget.record_id, description: "Fake blood",
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
      # Third-party payee fields are always visible (not tucked in a
      # collapsible that hid whether they were filled), with no "In use" flag
      # on a blank form.
      assert_includes response.body, "Pay someone else"
      assert_select "input#reimbursements_expense_form_payee_name_override"
      assert_not_includes response.body, "In use"
    end

    test "create writes a pending expense with receipts and redirects" do
      sign_in @user

      assert_difference "::Reimbursements::Expense.count", 1 do
        post :create, params: { reimbursements_expense_form: valid_form_params }
      end

      assert_redirected_to admin_reimbursements_expenses_path
      expense = ::Reimbursements::Expense.order(:id).last
      assert_equal "Pending", expense.status
      assert_equal @person, expense.person
      assert_equal @budget, expense.budget
      assert_in_delta 12.5, expense.amount
      assert_equal 1, expense.receipt_files.count
    end

    test "create as draft accepts gaps and writes Draft status" do
      sign_in @user

      assert_difference "::Reimbursements::Expense.count", 1 do
        post :create, params: { reimbursements_expense_form: {
          save_as_draft: "1", description: "Half-finished", receipts: [ receipt_upload ]
        } }
      end

      assert_redirected_to admin_reimbursements_expenses_path
      assert_equal "Draft", ::Reimbursements::Expense.order(:id).last.status
    end

    test "create degrades to a flash when the receipt upload fails" do
      sign_in @user
      store = ::Reimbursements::DatabaseStore.new
      store.define_singleton_method(:attach_receipt!) do |*|
        raise ::Reimbursements::Airtable::Error.new("upload failed", status: 500)
      end
      BaseController.store_builder = -> { store }

      assert_difference "::Reimbursements::Expense.count", 1 do
        post :create, params: { reimbursements_expense_form: valid_form_params }
      end

      expense = ::Reimbursements::Expense.order(:id).last
      assert_redirected_to edit_admin_reimbursements_expense_path(expense.record_id)
      assert_match(/uploading the receipt failed/, flash[:alert])
      assert_equal 0, expense.receipt_files.count
    end

    test "extract rejects unusable files without calling gemini" do
      sign_in @user
      BaseController.extractor_builder = -> { raise "extractor must not be built" }

      # An executable disguised with a .pdf filename and declared content_type:
      # content-type filtering is based on the actual bytes (Marcel), not the
      # declared/filename-implied type, so a mismatched-but-real PDF must NOT
      # be what's used here to prove rejection.
      post :extract, params: { receipts: [ fixture_file_upload("disguised_executable.pdf", "application/pdf") ] }

      assert_response :success
      assert_not response.parsed_body["ok"]
    end

    test "create without a receipt re-renders and writes nothing" do
      sign_in @user

      assert_no_difference "::Reimbursements::Expense.count" do
        post :create, params: { reimbursements_expense_form: valid_form_params.except(:receipts) }
      end

      assert_response :unprocessable_entity
    end

    test "create without vat acknowledgement soft-blocks when vat not itemised" do
      sign_in @user
      params = valid_form_params.merge(vat_itemised: "false", amount_excl_vat: "12.50")

      assert_no_difference "::Reimbursements::Expense.count" do
        post :create, params: { reimbursements_expense_form: params }
      end
      assert_response :unprocessable_entity

      assert_difference "::Reimbursements::Expense.count", 1 do
        post :create, params: { reimbursements_expense_form: params.merge(vat_acknowledged: "1", receipts: [ receipt_upload ]) }
      end
      assert_redirected_to admin_reimbursements_expenses_path
    end

    test "extract returns the extraction as json" do
      sign_in @user
      extraction = ::Reimbursements::Extractor::Extraction.new(
        merchant: "EBS", total_amount: BigDecimal("12.5"), vat_amount: BigDecimal("2.08"),
        vat_itemised: true, suggested_description: "Props",
        suggested_budget_record_id: @budget.record_id, suggested_payment_reference: "PROPS"
      )
      BaseController.extractor_builder = -> { FakeExtractor.new(extraction) }

      post :extract, params: { receipts: [ receipt_upload ] }

      assert_response :success
      body = response.parsed_body
      assert body["ok"]
      assert_equal "12.5", body["total_amount"]
      assert_equal "10.42", body["amount_excl_vat"]
      assert_equal @budget.record_id, body["suggested_budget_record_id"]
    end

    test "extract falls back to the total when excl-VAT is the zero not-yet-known sentinel" do
      sign_in @user
      # vat_itemised with total == vat gives amount_excl_vat a genuine zero
      # (not nil) -- 0 is truthy in Ruby, so a plain || wouldn't have fallen
      # back to total_amount here.
      extraction = ::Reimbursements::Extractor::Extraction.new(
        merchant: "EBS", total_amount: BigDecimal("12.5"), vat_amount: BigDecimal("12.5"),
        vat_itemised: true, suggested_description: "Props",
        suggested_budget_record_id: @budget.record_id, suggested_payment_reference: "PROPS"
      )
      BaseController.extractor_builder = -> { FakeExtractor.new(extraction) }

      post :extract, params: { receipts: [ receipt_upload ] }

      assert_response :success
      body = response.parsed_body
      assert body["ok"]
      assert_equal "12.5", body["total_amount"]
      assert_equal "12.5", body["amount_excl_vat"]
    end

    test "extract reports failure as ok false" do
      sign_in @user
      BaseController.extractor_builder = -> { FakeExtractor.new(::Reimbursements::Extractor::Extraction.new(error: "no key")) }

      post :extract, params: { receipts: [ receipt_upload ] }

      assert_response :success
      assert_not response.parsed_body["ok"]
    end

    test "edit refetches once when the cached airtable list is stale (email-in link)" do
      use_fake_airtable_store
      sign_in @user
      get :index # warms the expense cache without the email-in expense

      @client.list_records(:expenses) << airtable_expense_record(
        id: "recExpMail", payee_id: @person.record_id, description: "Emailed taxi receipt"
      )

      get :edit, params: { id: "recExpMail" }

      assert_response :success
      assert_includes response.body, "Emailed taxi receipt"
    end

    test "edit renders the prefilled form for an own pending expense" do
      sign_in @user

      get :edit, params: { id: @expense.record_id }

      assert_response :success
      assert_includes response.body, "Fake blood"
      assert_includes response.body, "receipt.pdf"
    end

    test "edit 404s for another person's expense" do
      sign_in @user

      get :edit, params: { id: @other_expense.record_id }

      assert_response :not_found
    end

    # --- Read-only show (view a claim after the editable window) -----------

    test "show renders an own expense read-only at any status, with no remove control" do
      approved = create_reimbursements_expense(person: @person, budget: @budget,
                                               status: ::Reimbursements::Status::APPROVED,
                                               description: "Van hire")
      sign_in @user

      get :show, params: { id: approved.record_id }

      assert_response :success
      assert_includes response.body, "Van hire"
      assert_includes response.body, "Approved"
      # No editable expense fields and no receipt-remove control on the
      # read-only page (both are present on the edit page — this discriminates it).
      assert_select "input[name='reimbursements_expense_form[amount]']", 0
      assert_select "button[data-action='receipts-upload#remove']", 0
    end

    test "show 404s for another person's expense" do
      sign_in @user

      get :show, params: { id: @other_expense.record_id }

      assert_response :not_found
    end

    test "the index links each row to its read-only view" do
      sign_in @user

      get :index

      assert_select "a[href=?]", admin_reimbursements_expense_path(@expense.record_id), text: "View"
    end

    # --- Draft/submit boundary: state-aware labels + actions --------------

    def own_draft(**attrs)
      create_reimbursements_expense(person: @person, budget: @budget,
                                    status: ::Reimbursements::Status::DRAFT, **attrs)
    end

    test "editing a Pending claim labels the primary Save changes and the withdraw button, which confirms" do
      sign_in @user

      get :edit, params: { id: @expense.record_id } # @expense is Pending

      assert_select "input[type=submit][value='Save changes']"
      assert_select "button[name='reimbursements_expense_form[save_as_draft]'][data-turbo-confirm*=?]",
                    "out of the finance team's queue"
      assert_includes response.body, "Withdraw back to draft"
    end

    test "editing a Draft labels the primary Submit expense and offers Delete draft" do
      draft = own_draft
      sign_in @user

      get :edit, params: { id: draft.record_id }

      assert_select "input[type=submit][value='Submit expense']"
      # Delete-draft button (a button_to DELETE with a confirm).
      assert_select "form[action=?][method=post]", admin_reimbursements_expense_path(draft.record_id) do
        assert_select "input[name=_method][value=delete]", 1
      end
      assert_includes response.body, "Delete draft"
    end

    test "destroy deletes an own draft" do
      draft = own_draft
      sign_in @user

      delete :destroy, params: { id: draft.record_id }

      assert_redirected_to admin_reimbursements_expenses_path
      assert_match(/draft deleted/i, flash[:notice])
      assert_not ::Reimbursements::Expense.exists?(draft.id)
    end

    test "destroy refuses a non-draft (Pending) claim" do
      sign_in @user

      delete :destroy, params: { id: @expense.record_id } # Pending

      assert_redirected_to admin_reimbursements_expenses_path
      assert_match(/only a draft can be deleted/i, flash[:alert])
      assert ::Reimbursements::Expense.exists?(@expense.id)
    end

    test "destroy 404s for another person's draft" do
      sign_in @user

      delete :destroy, params: { id: @other_expense.record_id }

      assert_response :not_found
      assert ::Reimbursements::Expense.exists?(@other_expense.id)
    end

    # A race: the producer follows an Edit link on a stale list for their own
    # claim that review has since picked up. Fail gracefully (friendly flash
    # redirect) rather than showing a bare 404.
    def own_non_editable_expense
      create_reimbursements_expense(person: @person, budget: @budget,
                                    status: ::Reimbursements::Status::APPROVED,
                                    description: "Locked claim")
    end

    test "edit redirects with a flash when an own claim is no longer editable" do
      approved = own_non_editable_expense
      sign_in @user

      get :edit, params: { id: approved.record_id }

      assert_redirected_to admin_reimbursements_expenses_path
      assert_match(/finance team/, flash[:warning])
    end

    test "update redirects with a flash when an own claim is no longer editable" do
      approved = own_non_editable_expense
      sign_in @user

      patch :update, params: { id: approved.record_id,
                               reimbursements_expense_form: valid_form_params.except(:receipts) }

      assert_redirected_to admin_reimbursements_expenses_path
      assert_match(/finance team/, flash[:warning])
      assert_equal "Locked claim", approved.reload.description, "nothing was written"
    end

    test "update writes changed fields without requiring a new receipt" do
      sign_in @user

      patch :update, params: { id: @expense.record_id,
                               reimbursements_expense_form: valid_form_params.except(:receipts).merge(description: "Even more fake blood") }

      assert_redirected_to admin_reimbursements_expenses_path
      @expense.reload
      assert_equal "Even more fake blood", @expense.description
      assert_equal "Pending", @expense.status, "a full (non-draft) save submits the expense"
      assert_equal 1, @expense.receipt_files.count, "no new receipt was uploaded"
    end

    test "submitting a receipt-less draft demands a receipt" do
      bare_draft = own_draft(description: "Bare draft", receipt: false)
      sign_in @user

      patch :update, params: { id: bare_draft.record_id,
                               reimbursements_expense_form: valid_form_params.except(:receipts) }
      assert_response :unprocessable_entity
      assert_equal "Bare draft", bare_draft.reload.description, "nothing was written"

      patch :update, params: { id: bare_draft.record_id, reimbursements_expense_form: valid_form_params }
      assert_redirected_to admin_reimbursements_expenses_path
      bare_draft.reload
      assert_equal 1, bare_draft.receipt_files.count
      assert_equal "Pending", bare_draft.status
    end

    test "update rejects invalid input without writing" do
      sign_in @user

      patch :update, params: { id: @expense.record_id,
                               reimbursements_expense_form: valid_form_params.except(:receipts).merge(amount: "") }

      assert_response :unprocessable_entity
      assert_in_delta 12.5, @expense.reload.amount, 0.001, "nothing was written"
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
