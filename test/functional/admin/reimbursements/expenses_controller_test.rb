require "test_helper"

module Admin
  module Reimbursements
  class ExpensesControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    setup do
      grant_producer_permission(users(:member))
      grant_producer_permission(users(:member_with_phone_number))
      @user = users(:member)
      @person = create_reimbursements_person(email: @user.email)
      @other_person = create_reimbursements_person(name: "Other Person", email: "other@example.com")
      @budget = create_reimbursements_budget
      @expense = create_reimbursements_expense(person: @person, budget: @budget)
      @other_expense = create_reimbursements_expense(person: @other_person, budget: @budget,
                                                     description: "Someone else's")
    end

    teardown do
      BaseController.store_builder = BaseController::DEFAULT_STORE_BUILDER
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

    test "index lists only the current user's expenses and links them to their payee record" do
      sign_in @user
      assert_nil @user.reimbursements_person_id

      get :index

      assert_response :success
      assert_equal @person.id, @user.reload.reimbursements_person_id
      assert_equal [ @expense.record_id ], assigns(:expenses).map(&:record_id)
      assert_includes response.body, "Fake blood"
      assert_not_includes response.body, "Someone else&#39;s"
      assert_select "th", text: "Submitted"
      assert_select "th", text: "Created", count: 0
      assert_select "a[href=?]", admin_reimbursements_expense_path(@expense.record_id), text: "View"
      assert_includes response.body, "add your payment details"
    end

    test "refresh redirects to a clean url" do
      sign_in @user

      get :index, params: { refresh: 1 }

      assert_redirected_to admin_reimbursements_expenses_path
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
        payment_reference: "PROPS PAT",
        receipts: [ receipt_upload ]
      }
    end

    # active_budgets is not cost-centre scoped, so the picker must say whose
    # line each is.
    test "the budget picker names each line's cost centre" do
      centre = create_reimbursements_cost_centre(key: "picker-centre", name: "Bedlam Fringe",
                                                 eusa_code: "F41", short_code: "BF")
      create_reimbursements_budget(name: "Marketing", cost_centre: centre)
      sign_in @user

      get :new

      assert_response :success
      assert_select "option", text: "BF - Marketing"
    end

    test "new renders the receipt-first form" do
      sign_in @user

      get :new

      assert_response :success
      assert_includes response.body, "reimbursements-receipt"
      assert_includes response.body, "Props"
      # Payee fields always visible, with no "In use" flag on a blank form.
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

    # --- The international rail ---------------------------------------------

    test "create writes an international claim from the euro amount alone" do
      sign_in @user

      post :create, params: { reimbursements_expense_form: valid_form_params.merge(
        payment_method: ::Reimbursements::Expense::PAYMENT_METHOD_INTERNATIONAL,
        amount: "", amount_excl_vat: "", foreign_amount: "266.69",
        payee_name_override: "Ausland GmbH",
        iban_override: "DE89 3704 0044 0532 0130 00", bic_override: "deutdeff500"
      ) }

      assert_redirected_to admin_reimbursements_expenses_path
      expense = ::Reimbursements::Expense.order(:id).last
      assert expense.international?
      assert_in_delta 266.69, expense.foreign_amount
      assert_equal ::Reimbursements::Expense::CURRENCY_EUR, expense.foreign_currency
      assert_equal "DE89370400440532013000", expense.iban_override
      assert_equal "DEUTDEFF500", expense.bic_override
      # Finance supplies this at review.
      assert_nil expense.amount
      assert_equal "Pending", expense.status
    end

    # Converted at intake, so every downstream reader gets an ordinary JPEG.
    test "create stores an iPhone HEIC photo as a JPEG named .jpg" do
      sign_in @user

      post :create, params: { reimbursements_expense_form:
        valid_form_params.merge(receipts: [ fixture_file_upload("reimbursements_receipt.heic", "image/heic") ]) }

      assert_redirected_to admin_reimbursements_expenses_path
      receipt = ::Reimbursements::Expense.order(:id).last.receipt_files.sole
      assert_equal "image/jpeg", receipt.content_type
      assert_equal "reimbursements_receipt.jpg", receipt.filename.to_s
      assert_equal "image/jpeg", Marcel::MimeType.for(StringIO.new(receipt.download)),
                   "the stored bytes must actually be a readable JPEG"
    end

    # A damaged photo (or libvips without HEIF) is a validation error, not a 500.
    test "create re-renders with a friendly error when a photo can't be read" do
      sign_in @user

      assert_no_difference "::Reimbursements::Expense.count" do
        post :create, params: { reimbursements_expense_form:
          valid_form_params.merge(receipts: [ fixture_file_upload("truncated_receipt.heic", "image/heic") ]) }
      end

      assert_response :unprocessable_entity
      assert_match(/couldn&#39;t read truncated_receipt\.heic/, response.body)
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
        raise "upload failed"
      end
      BaseController.store_builder = ->(**) { store }

      assert_difference "::Reimbursements::Expense.count", 1 do
        post :create, params: { reimbursements_expense_form: valid_form_params }
      end

      expense = ::Reimbursements::Expense.order(:id).last
      assert_redirected_to edit_admin_reimbursements_expense_path(expense.record_id)
      assert_match(/uploading the receipt failed/, flash[:alert])
      assert_equal 0, expense.receipt_files.count
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
      # No VAT breakdown: the ex-VAT amount is not below the total.
      params = valid_form_params.merge(amount: "12.50", amount_excl_vat: "12.50")

      assert_no_difference "::Reimbursements::Expense.count" do
        post :create, params: { reimbursements_expense_form: params }
      end
      assert_response :unprocessable_entity

      assert_difference "::Reimbursements::Expense.count", 1 do
        post :create, params: { reimbursements_expense_form: params.merge(vat_acknowledged: "1", receipts: [ receipt_upload ]) }
      end
      assert_redirected_to admin_reimbursements_expenses_path
    end

    # A :base error has no field to render under.
    test "create shows the reason a base-level rule blocked the form" do
      sign_in @user
      params = valid_form_params.merge(payee_name_override: "Acme Props Ltd")

      post :create, params: { reimbursements_expense_form: params }

      assert_response :unprocessable_entity
      assert_includes response.body, "fill in all three: payee name, sort code, and account number"
    end

    # EffectivePayee would fall back to the submitter's own details.
    test "create rejects an invoice with no third-party payee details" do
      sign_in @user
      params = valid_form_params.merge(expense_type: ::Reimbursements::Expense::TYPE_INVOICE)

      assert_no_difference "::Reimbursements::Expense.count" do
        post :create, params: { reimbursements_expense_form: params }
      end

      assert_response :unprocessable_entity
      assert_includes response.body, "change the type to Reimbursement"

      with_payee = params.merge(receipts: [ receipt_upload ], payee_name_override: "Acme Props Ltd",
                                sort_code_override: "12-34-56", account_number_override: "12345678")
      assert_difference "::Reimbursements::Expense.count", 1 do
        post :create, params: { reimbursements_expense_form: with_payee }
      end
      assert_redirected_to admin_reimbursements_expenses_path
      assert_equal "Acme Props Ltd", ::Reimbursements::Expense.order(:id).last.payee_name_override
    end

    test "edit renders the prefilled form for an own pending expense" do
      sign_in @user

      get :edit, params: { id: @expense.record_id }

      assert_response :success
      assert_includes response.body, "Fake blood"
      assert_includes response.body, "receipt.pdf"
    end

    [ [ :get, :show ], [ :get, :edit ], [ :delete, :destroy ] ].each do |verb, action|
      test "#{action} 404s for another person's expense" do
        sign_in @user

        public_send(verb, action, params: { id: @other_expense.record_id })

        assert_response :not_found
        assert ::Reimbursements::Expense.exists?(@other_expense.id)
      end
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
      assert_select "input[name='reimbursements_expense_form[amount]']", 0
      assert_select "button[data-action='receipts-upload#remove']", 0
    end

    # An international claim has no UK overrides, so reading the sort code and
    # account number would print the submitter's own account as the payee's.
    test "show prints a third-party payee's own rail's details, not the submitter's account" do
      @person.create_payment_details!(sort_code: "11-22-33", account_number: "87654321")
      international = create_reimbursements_expense(
        person: @person, budget: @budget, payment_method: ::Reimbursements::Expense::PAYMENT_METHOD_INTERNATIONAL,
        payee_name_override: "Ausland GmbH", iban_override: "DE89370400440532013000",
        bic_override: "DEUTDEFF500"
      )
      uk = create_reimbursements_expense(person: @person, budget: @budget, payee_name_override: "Venue Ltd",
                                         sort_code_override: "20-00-00", account_number_override: "12345678")
      sign_in @user

      get :show, params: { id: international.record_id }
      assert_includes response.body, "Ausland GmbH"
      assert_includes response.body, "DE89 3704 0044 0532 0130 00"
      assert_includes response.body, "DEUTDEFF500"
      assert_not_includes response.body, "87654321"

      get :show, params: { id: uk.record_id }
      assert_includes response.body, "20-00-00"
      assert_includes response.body, "12345678"
    end

    # before_create stamps submitted_at on a draft too, so it is when it started.
    test "show labels the claim's date Submitted, and Started while it is a draft" do
      submitted = create_reimbursements_expense(person: @person, budget: @budget,
                                                status: ::Reimbursements::Status::PENDING)
      draft = create_reimbursements_expense(person: @person, budget: @budget,
                                            status: ::Reimbursements::Status::DRAFT)
      sign_in @user

      get :show, params: { id: submitted.record_id }
      assert_select "dt", text: "Submitted"
      assert_select "dt", text: "Created", count: 0

      get :show, params: { id: draft.record_id }
      assert_select "dt", text: "Started"
      assert_select "dt", text: "Submitted", count: 0
    end

    # --- In-page receipt viewer -------------------------------------------

    test "show renders the shared in-page receipt viewer, closed and unloaded" do
      sign_in @user

      get :show, params: { id: @expense.record_id }

      assert_response :success
      receipt = @expense.receipts.sole
      assert_select "div[data-controller='fancybox receipt-viewer']"
      assert_select "button[data-action='receipt-viewer#show'][aria-expanded='false']" do |buttons|
        assert_equal "View receipt 1 of 1, receipt.pdf", buttons.first["aria-label"]
      end
      assert_select "img[src=?]", receipt.preview_url
      # The pane is closed and its frame not yet loaded.
      assert_select "div#receipt-pane-#{@expense.record_id}[hidden]"
      assert_select "iframe[data-src=?]", receipt.url
      assert_select "iframe[src]", 0
    end

    test "edit renders the viewer with the producer's own remove control" do
      sign_in @user

      get :edit, params: { id: @expense.record_id }

      assert_response :success
      assert_select "div[data-controller='fancybox receipt-viewer']"
      assert_select "button[data-action='receipts-upload#remove']", 1
      assert_select "iframe[data-src]", 1
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
      # Delete draft posts its own form, apart from the update's same URL.
      assert_select "form[action=?][method=post][data-turbo-confirm]",
                    admin_reimbursements_expense_path(draft.record_id) do
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

    # A stale Edit link for a claim review has since picked up.
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

    # --- A budget that vanished while the form was open ----------------------
    # Honeybadger 134234926: a deleted budget 500ed the submit and lost the claim.

    # A separate budget, so deleting it can't take @expense's own row with it.
    def spare_budget(**attrs)
      create_reimbursements_budget(name: "Costumes", nominal_code: "4100", **attrs)
    end

    # A deactivated budget still satisfies the FK, so it used to charge a retired line.
    { "deleted" => ->(budget) { budget.destroy! },
      "deactivated" => ->(budget) { budget.update!(active: false) } }.each do |how, vanish|
      test "create re-renders keeping the input when the picked budget was #{how}" do
        sign_in @user
        gone = spare_budget
        params = valid_form_params.merge(budget_record_id: gone.record_id,
                                         description: "Blood capsules and a wig")
        vanish.call(gone)

        assert_no_difference "::Reimbursements::Expense.count" do
          post :create, params: { reimbursements_expense_form: params }
        end

        assert_response :unprocessable_entity
        assert_match(/no longer available/, response.body)
        assert_includes response.body, "Blood capsules and a wig",
                        "the producer's typing must survive the failed submit"
        assert_includes response.body, "PROPS PAT"
      end
    end

    # The notice says the budget went, so they can re-pick it.
    test "create as a draft drops the vanished budget and still saves" do
      sign_in @user
      doomed = spare_budget
      params = valid_form_params.merge(budget_record_id: doomed.record_id,
                                       description: "Half-finished", save_as_draft: "1")
      doomed.destroy!

      assert_difference "::Reimbursements::Expense.count", 1 do
        post :create, params: { reimbursements_expense_form: params }
      end

      assert_redirected_to admin_reimbursements_expenses_path
      expense = ::Reimbursements::Expense.order(:id).last
      assert_equal "Draft", expense.status
      assert_nil expense.budget
      assert_equal "Half-finished", expense.description
      assert_match(/budget/i, flash[:notice])
    end

    test "update re-renders keeping the input when the picked budget was deleted" do
      sign_in @user
      doomed = spare_budget
      params = valid_form_params.except(:receipts).merge(budget_record_id: doomed.record_id,
                                                         description: "Edited description")
      doomed.destroy!

      patch :update, params: { id: @expense.record_id, reimbursements_expense_form: params }

      assert_response :unprocessable_entity
      assert_match(/no longer available/, response.body)
      assert_includes response.body, "Edited description"
      assert_equal "Fake blood", @expense.reload.description, "nothing was written"
    end

    # A delete landing between the validation and the insert.
    test "create renders the form when the store reports the budget gone mid-write" do
      sign_in @user
      store = ::Reimbursements::DatabaseStore.new
      store.define_singleton_method(:create_expense!) do |*|
        raise ::Reimbursements::DatabaseStore::BudgetGoneError
      end
      BaseController.store_builder = ->(**) { store }

      assert_no_difference "::Reimbursements::Expense.count" do
        post :create, params: { reimbursements_expense_form:
          valid_form_params.merge(description: "Raced away") }
      end

      assert_response :unprocessable_entity
      assert_match(/no longer available/, response.body)
      assert_includes response.body, "Raced away"
    end
  end
  end
end
