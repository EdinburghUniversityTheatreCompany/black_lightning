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

    test "refresh redirects to a clean url" do
      sign_in @user

      get :index, params: { refresh: 1 }

      assert_redirected_to admin_reimbursements_expenses_path
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

    # A plain (no bank trio) extraction; overrides tune individual fields.
    def extraction_basic(**overrides)
      ::Reimbursements::Extractor::Extraction.new(
        merchant: "EBS", total_amount: BigDecimal("12.5"), vat_amount: BigDecimal("2.08"),
        vat_itemised: true, suggested_description: "Props",
        suggested_budget_record_id: @budget.record_id, suggested_payment_reference: "PROPS", **overrides
      )
    end

    # An extraction that carries the payee bank trio, so the self/invoice mode
    # tests can assert the controller gates those fields on the mode.
    def extraction_with_bank(**overrides)
      extraction_basic(merchant: "Acme", total_amount: BigDecimal("120.0"),
                       vat_amount: BigDecimal("20.0"), suggested_description: "Set timber",
                       suggested_payment_reference: "INV-1001", payee_name: "Acme Props Ltd",
                       sort_code: "12-34-56", account_number: "12345678", **overrides)
    end

    # POST the extract endpoint in a given mode and return the parsed JSON body.
    def extract_body(extraction, mode:)
      BaseController.extractor_builder = -> { FakeExtractor.new(extraction) }
      post :extract, params: { mode: mode, receipts: [ receipt_upload ] }
      assert_response :success
      response.parsed_body
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

    # The disclosure has to describe BOTH uses of the receipt, because one answer
    # governs both: a disclosure that mentions only prefilling makes the finance
    # check run on receipts whose submitters never agreed to that use.
    test "new discloses both AI uses of the receipt and that declining costs nothing" do
      sign_in @user

      get :new

      assert_includes response.body, "so finance can check your claim against it"
      assert_includes response.body, "We use Gemini's free tier"
      assert_includes response.body, "Nothing else about your claim changes."
      # The three option labels are Mick's wording and must stay verbatim.
      assert_includes response.body, "Yes, to be reimbursed to myself"
      assert_includes response.body, "Yes, as an invoice paid out to the bank details listed on the invoice"
      assert_includes response.body, "No, I will fill in all the details myself"
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

    # The receipt form's consent radio governs BOTH AI uses of the receipt
    # (prefill now, the finance check later), so the choice has to be persisted
    # on create. It cannot be inferred from the extract POST: a submitter who
    # picks "No" never fires one.
    test "create records consent for each of the three receipt scan choices" do
      sign_in @user

      { "self" => true, "invoice" => true, "no" => false }.each do |choice, expected|
        post :create, params: { reimbursements_expense_form:
          valid_form_params.merge(receipt_scan_consent: choice, receipts: [ receipt_upload ]) }

        assert_equal expected, ::Reimbursements::Expense.order(:id).last.ai_processing_consent,
                     "receipt_scan_consent=#{choice} must persist as #{expected.inspect}"
      end
    end

    # No radio picked at all (JavaScript off, so the choice was never revealed)
    # is "never asked", which must stay distinguishable from a refusal.
    test "create leaves consent nil when no scan choice was made" do
      sign_in @user

      post :create, params: { reimbursements_expense_form: valid_form_params }

      assert_nil ::Reimbursements::Expense.order(:id).last.ai_processing_consent
    end

    # Consent is the submitter's to give, so a garbage value is not consent.
    test "create treats an unrecognised scan choice as no consent" do
      sign_in @user

      post :create, params: { reimbursements_expense_form:
        valid_form_params.merge(receipt_scan_consent: "yes-please") }

      assert_nil ::Reimbursements::Expense.order(:id).last.ai_processing_consent
    end

    # iOS photographs default to HEIC. The conversion happens at intake so the
    # stored blob is an ordinary JPEG for every downstream consumer (viewer,
    # Gemini, the SharePoint offload, the receipts mailed with a BACS batch).
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

    test "create keeps an ordinary PDF receipt exactly as uploaded" do
      sign_in @user

      post :create, params: { reimbursements_expense_form: valid_form_params }

      receipt = ::Reimbursements::Expense.order(:id).last.receipt_files.sole
      assert_equal "application/pdf", receipt.content_type
      assert_equal "reimbursements_receipt.pdf", receipt.filename.to_s
      assert_equal File.binread(Rails.root.join("test/fixtures/files/reimbursements_receipt.pdf")),
                   receipt.download
    end

    # A damaged photo (or a libvips built without HEIF support) must come back
    # through the normal validation path, not as a 500.
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
      post :extract, params: { mode: "self",
                               receipts: [ fixture_file_upload("disguised_executable.pdf", "application/pdf") ] }

      assert_response :success
      assert_not response.parsed_body["ok"]
    end

    # A String has #size, so it clears the byte check and then reaches
    # ReceiptContentType.allowed_upload?'s #read — an unrescued NoMethodError
    # (500) from any authenticated producer who hand-crafts the post.
    test "extract rejects a string receipts param instead of raising" do
      sign_in @user
      BaseController.extractor_builder = -> { raise "extractor must not be built" }

      post :extract, params: { mode: "self", receipts: [ "not-a-file" ] }

      assert_response :success
      assert_not response.parsed_body["ok"]
      assert_equal "no usable receipt files", response.parsed_body["error"]
    end

    test "extract rejects an unknown mode with a 422 before touching gemini" do
      sign_in @user
      BaseController.extractor_builder = -> { raise "extractor must not be built" }

      post :extract, params: { mode: "steal", receipts: [ receipt_upload ] }

      assert_response :unprocessable_entity
      assert_not response.parsed_body["ok"]
    end

    test "extract rejects a missing mode with a 422" do
      sign_in @user
      BaseController.extractor_builder = -> { raise "extractor must not be built" }

      post :extract, params: { receipts: [ receipt_upload ] }

      assert_response :unprocessable_entity
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

    # A :base error has no field to render under, so the generic "review the
    # problems below" banner used to be ALL the producer saw — a form that
    # failed with no stated reason. The shared form partial lists them now.
    test "create shows the reason a base-level rule blocked the form" do
      sign_in @user
      params = valid_form_params.merge(payee_name_override: "Acme Props Ltd")

      post :create, params: { reimbursements_expense_form: params }

      assert_response :unprocessable_entity
      assert_includes response.body, "fill in all three: payee name, sort code, and account number"
    end

    # The submitter's own bank details would otherwise stand in for the missing
    # payee (EffectivePayee's fallback), so the claim would pay them for a bill
    # they never paid — and review's "no bank details" block can't see it.
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

    test "extract returns the extraction as json" do
      sign_in @user

      body = extract_body(extraction_basic, mode: "self")

      assert body["ok"]
      assert_equal "12.5", body["total_amount"]
      assert_equal "10.42", body["amount_excl_vat"]
      assert_equal @budget.record_id, body["suggested_budget_record_id"]
    end

    test "extract in self mode never returns bank details, even if the model volunteers them" do
      sign_in @user
      # A self-mode scan must not surface payee bank details. The fake extractor
      # supplies them anyway; the controller must strip them for self mode.
      body = extract_body(extraction_with_bank, mode: "self")

      assert body["ok"]
      assert_not body.key?("payee_name"), "self mode must omit the payee name"
      assert_not body.key?("sort_code"), "self mode must omit the sort code"
      assert_not body.key?("account_number"), "self mode must omit the account number"
    end

    test "extract in invoice mode passes the printed bank details through" do
      sign_in @user

      body = extract_body(extraction_with_bank, mode: "invoice")

      assert body["ok"]
      assert_equal "Acme Props Ltd", body["payee_name"]
      assert_equal "12-34-56", body["sort_code"]
      assert_equal "12345678", body["account_number"]
    end

    test "extract falls back to the total when excl-VAT is the zero not-yet-known sentinel" do
      sign_in @user
      # vat_itemised with total == vat gives amount_excl_vat a genuine zero
      # (not nil) -- 0 is truthy in Ruby, so a plain || wouldn't have fallen
      # back to total_amount here.
      body = extract_body(extraction_basic(vat_amount: BigDecimal("12.5")), mode: "self")

      assert body["ok"]
      assert_equal "12.5", body["total_amount"]
      assert_equal "12.5", body["amount_excl_vat"]
    end

    test "extract reports failure as ok false" do
      sign_in @user

      body = extract_body(::Reimbursements::Extractor::Extraction.new(error: "no key"), mode: "self")

      assert_not body["ok"]
    end

    test "edit finds an own expense created out-of-band (e.g. the email-in poll job)" do
      sign_in @user
      get :index # the user's list is warmed without the email-in expense

      emailed = create_reimbursements_expense(person: @person, budget: @budget,
                                              description: "Emailed taxi receipt")

      get :edit, params: { id: emailed.record_id }

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

    # --- In-page receipt viewer -------------------------------------------
    # The producer reads their own receipt in the page, through the same shared
    # partial the Review queue and the finance pages use.

    test "show renders the shared in-page receipt viewer, closed and unloaded" do
      sign_in @user

      get :show, params: { id: @expense.record_id }

      assert_response :success
      receipt = @expense.receipts.sole
      assert_select "div[data-controller='fancybox receipt-viewer']"
      assert_select "button[data-action='receipt-viewer#show'][aria-expanded='false']" do |buttons|
        assert_equal "View receipt 1 of 1, receipt.pdf", buttons.first["aria-label"]
      end
      # A PDF gets a real first-page thumbnail, not a generic document icon.
      assert_select "img[src=?]", receipt.preview_url
      # The pane is present but closed, and its frame carries no src yet.
      assert_select "div#receipt-pane-#{@expense.record_id}[hidden]"
      assert_select "iframe[data-src=?]", receipt.inline_url
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
