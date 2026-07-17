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

        # Rejection emails now go through the Graph notifier; inject a real
        # Notifier over a recording FakeGraphClient so tests assert the send
        # (mailbox / recipient / subject / body) rather than an enqueued mailer.
        @graph = FakeGraphClient.new
        ReviewController.notifier_builder =
          ->(mailbox:) { ::Reimbursements::Notifier.new(mailbox: mailbox, graph: @graph) }
      end

      teardown do
        BaseController.store_builder = -> { ::Reimbursements::Store.new }
        ReviewController.checker_builder = -> { MC.default_checker }
        ReviewController.notifier_builder =
          ->(mailbox:) { ::Reimbursements::Notifier.new(mailbox: mailbox) }
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

      def image_receipt(tag)
        { "id" => "attImg#{tag}", "filename" => "receipt#{tag}.jpg",
          "url" => "https://airtable/img#{tag}.jpg", "size" => 100, "type" => "image/jpeg",
          "thumbnails" => { "large" => { "url" => "https://airtable/thumb#{tag}.jpg" } } }
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
        # Distinct amounts so these two don't incidentally look like duplicates
        # of each other (same payee, no submitted_at — see #find_duplicate_submissions).
        ready = pending_expense(id: "recReady", amount: 111.0, payment_reference: "PROPS PAT")
        attention = pending_expense(id: "recAttn", amount: 222.0, amount_excl_vat: nil) # missing excl VAT
        approved = pending_expense(id: "recAppr").tap { |r| r["fields"][EXP[:status]] = "Approved" }
        rebuild_store(expenses: [ ready, attention, approved ])
        sign_in @user

        get :index

        assert_response :success
        assert_equal %w[recReady], assigns(:ready).map(&:record_id)
        assert_equal %w[recAttn], assigns(:attention).map(&:record_id)
        assert_equal %w[recAppr], assigns(:approved).map(&:record_id)
      end

      test "the current tab is marked aria-current, the other is not" do
        rebuild_store(expenses: [ pending_expense(id: "recReady", payment_reference: "PROPS PAT") ])
        sign_in @user

        get :index, params: { tab: "approved" }

        assert_select "a[aria-current=page]", text: /Approved/
        assert_select "a[aria-current=page]", text: /Pending/, count: 0
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

      test "renders receipts in a fancybox gallery keyed per expense, still managed inline" do
        a = pending_expense(id: "recImgA", payment_reference: "PROPS PAT", receipts: [ image_receipt("A") ])
        b = pending_expense(id: "recImgB", payment_reference: "PROPS PAT", receipts: [ image_receipt("B") ])
        rebuild_store(expenses: [ a, b ])
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, 'data-controller="fancybox"'
        # Each card gets its own fancybox group so the lightbox pages within one expense.
        assert_includes response.body, 'data-fancybox="receipts-recImgA"'
        assert_includes response.body, 'data-fancybox="receipts-recImgB"'
        assert_includes response.body, "https://airtable/imgA.jpg"
        # Reviewers can still attach/detach receipts inline (per-tab review routes).
        assert_match(/Remove this receipt/, response.body)
        assert_includes response.body, admin_reimbursements_review_receipts_path("recImgA", tab: "pending")
      end

      test "renders a duplicate-submission warning" do
        first = pending_expense(id: "recDupA", amount: 12.5, payment_reference: "PROPS PAT")
        second = pending_expense(id: "recDupB", amount: 12.5, payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ first, second ])
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "Possible duplicate of"
        # A possible duplicate is otherwise clean (bank details, budget, amount
        # all fine) but must still land in Attention, not Ready — approving both
        # in two clicks would double-pay the same claim.
        assert_equal %w[recDupA recDupB], assigns(:attention).map(&:record_id).sort
        assert_empty assigns(:ready)
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

      test "re-kicks an AI check for an expense stuck on an error verdict" do
        errored = pending_expense(id: "recErrored", payment_reference: "PROPS PAT",
                                  overrides: { EXP[:ai_check_status] => "error" })
        rebuild_store(expenses: [ errored ])
        sign_in @user

        assert_enqueued_with(job: ::Reimbursements::AiCheckJob, args: [ "recErrored" ]) do
          get :index
        end
      end

      # --- Bulk actions ----------------------------------------------------

      test "the pending tab exposes bulk-select checkboxes and a bulk toolbar" do
        a = pending_expense(id: "recBulkA", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ a ])
        sign_in @user

        get :index

        assert_response :success
        assert_select "[data-controller~=?]", "bulk-review"
        assert_select "input[data-bulk-review-target=selectAll]"
        assert_select "form#bulk-review-form[action=?]",
                      admin_reimbursements_bulk_approve_review_path(tab: "pending")
        assert_select "input[type=checkbox][name=?][value=?][form=bulk-review-form]",
                      "expense_ids[]", "recBulkA"
        assert_select "input[data-bulk-review-target=rejectButton][data-turbo-confirm*=?]",
                      "email each producer"
      end

      test "a flagged card's Approve confirms with its reasons; a clean card's doesn't" do
        clean = pending_expense(id: "recClean", payment_reference: "PROPS PAT")
        # No receipts -> "no receipt" attention reason (advisory-only, so the
        # server never blocks it — this confirm is the only safety net).
        flagged = pending_expense(id: "recFlagged", payment_reference: "PROPS PAT", receipts: [])
        rebuild_store(expenses: [ clean, flagged ])
        sign_in @user

        get :index

        assert_response :success
        flagged_form = css_select("form[action*='#{admin_reimbursements_approve_review_path('recFlagged')}']").first
        assert_includes flagged_form["data-turbo-confirm"], "no receipt"
        assert_includes flagged_form["data-turbo-confirm"], "Approve anyway?"
        clean_form = css_select("form[action*='#{admin_reimbursements_approve_review_path('recClean')}']").first
        assert_nil clean_form["data-turbo-confirm"], "clean cards keep one-click approval"
        # The bulk toolbar's flagged-count confirm reads these markers.
        assert_select "input#select_recFlagged[data-flagged=true]"
        assert_select "input#select_recClean[data-flagged=false]"
      end

      test "bulk approve advances every selected pending expense" do
        a = pending_expense(id: "recBulkA", payment_reference: "PROPS PAT")
        b = pending_expense(id: "recBulkB", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ a, b ])
        sign_in @user

        patch :bulk_approve, params: { expense_ids: %w[recBulkA recBulkB] }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        statuses = @client.updated.map { |_t, id, f| [ id, f[EXP[:status]] ] }.sort
        assert_equal [ [ "recBulkA", "Approved" ], [ "recBulkB", "Approved" ] ], statuses
        assert_match(/2 approved/, flash[:notice])
      end

      test "bulk approve skips an expense that lacks bank details" do
        ok = pending_expense(id: "recBulkOk", payment_reference: "PROPS PAT")
        no_bank = pending_expense(id: "recBulkNB", payee_id: "recPer2", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ ok, no_bank ])
        sign_in @user

        patch :bulk_approve, params: { expense_ids: %w[recBulkOk recBulkNB] }

        updated_ids = @client.updated.map { |_t, id, _f| id }
        assert_equal [ "recBulkOk" ], updated_ids
        assert_match(/1 approved/, flash[:notice])
        assert_match(/1 skipped \(missing bank details, budget, or amount\)/, flash[:notice])
      end

      test "bulk approve with nothing selected writes nothing and reports it" do
        a = pending_expense(id: "recBulkA", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ a ])
        sign_in @user

        patch :bulk_approve, params: { expense_ids: [] }

        assert_match(/Select at least one/, flash[:alert])
        assert_empty @client.updated
      end

      test "bulk reject rejects each selected expense and emails each producer" do
        a = pending_expense(id: "recBulkA", payment_reference: "PROPS PAT")
        b = pending_expense(id: "recBulkB", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ a, b ])
        sign_in @user

        patch :bulk_reject, params: { expense_ids: %w[recBulkA recBulkB], rejection_reason: "Duplicate batch" }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        rejected = @client.updated.select { |_t, _id, f| f[EXP[:status]] == "Rejected" }
        assert_equal 2, rejected.size
        rejected.each { |_t, _id, f| assert_equal "Duplicate batch", f[EXP[:rejection_reason]] }
        assert_equal 2, @graph.send_mails.size
        assert_match(/2 rejected/, flash[:notice])
      end

      test "bulk reject requires a reason and writes nothing" do
        a = pending_expense(id: "recBulkA", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ a ])
        sign_in @user

        patch :bulk_reject, params: { expense_ids: %w[recBulkA], rejection_reason: "  " }

        assert_match(/reason is required/, flash[:alert])
        assert_empty @client.updated
        assert_empty @graph.send_mails
      end

      test "bulk actions ignore a stale selection of a non-pending expense" do
        approved = pending_expense(id: "recAppr").tap { |r| r["fields"][EXP[:status]] = "Approved" }
        rebuild_store(expenses: [ approved ])
        sign_in @user

        patch :bulk_approve, params: { expense_ids: %w[recAppr] }

        assert_empty @client.updated
        assert_match(/Select at least one/, flash[:alert])
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

      test "save rejects a budget_record_id that doesn't resolve to a real budget" do
        expense = pending_expense(id: "recEdit", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :save, params: { id: "recEdit", amount: "20.00", amount_excl_vat: "16.67",
                               description: "x", payment_reference: "y", budget_record_id: "recBudGone" }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/budget no longer exists/i, flash[:alert])
        assert_empty @client.updated
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

      test "save rejects a negative amount and writes nothing" do
        expense = pending_expense(id: "recEdit", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :save, params: { id: "recEdit", amount: "-5", amount_excl_vat: "16.67",
                               description: "x", budget_record_id: "recBud1" }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/valid amount/i, flash[:alert])
        assert_empty @client.updated
      end

      test "save rejects a non-numeric amount and writes nothing" do
        expense = pending_expense(id: "recEdit", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :save, params: { id: "recEdit", amount: "abc", amount_excl_vat: "16.67",
                               description: "x", budget_record_id: "recBud1" }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/valid amount/i, flash[:alert])
        assert_empty @client.updated
      end

      test "save rejects a negative excl-VAT amount and writes nothing" do
        expense = pending_expense(id: "recEdit", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :save, params: { id: "recEdit", amount: "20.00", amount_excl_vat: "-1",
                               description: "x", budget_record_id: "recBud1" }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/excl. VAT/i, flash[:alert])
        assert_empty @client.updated
      end

      test "save rejects an excl-VAT amount greater than the total and writes nothing" do
        expense = pending_expense(id: "recEdit", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :save, params: { id: "recEdit", amount: "20.00", amount_excl_vat: "25.00",
                               description: "x", budget_record_id: "recBud1" }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/can't be more than the total/i, flash[:alert])
        assert_empty @client.updated
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

      test "approve is blocked without a linked budget" do
        expense = airtable_expense_record(id: "recNoBudget", payee_id: "recPer1", budget_id: nil,
                                          status: "Pending", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :approve, params: { id: "recNoBudget" }

        assert_match(/without a budget linked/, flash[:alert])
        assert_empty @client.updated
      end

      test "approve is blocked without a non-zero excl-VAT amount" do
        expense = pending_expense(id: "recNoAmount", amount_excl_vat: 0, payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :approve, params: { id: "recNoAmount" }

        assert_match(/without an amount excluding VAT/, flash[:alert])
        assert_empty @client.updated
      end

      test "a stale approve against an already-Approved expense is a no-op, not a re-approve" do
        already = airtable_expense_record(id: "recAlreadyApproved", payee_id: "recPer1",
                                          budget_id: "recBud1", status: "Approved", auto_number: 9)
        rebuild_store(expenses: [ already ])
        sign_in @user

        patch :approve, params: { id: "recAlreadyApproved" }

        assert_match(/no longer Pending/, flash[:alert])
        assert_empty @client.updated
      end

      # --- Reject ----------------------------------------------------------

      test "the reject form asks for confirmation before emailing the producer" do
        expense = pending_expense(id: "recRej", auto_number: 42, payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        get :index

        assert_response :success
        assert_select "form[action=?][data-turbo-confirm*=?]",
                      admin_reimbursements_reject_review_path("recRej", tab: "pending"),
                      "Reject #42 and email the producer"
      end

      test "reject requires a reason" do
        expense = pending_expense(id: "recRej", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :reject, params: { id: "recRej", rejection_reason: "  " }

        assert_match(/reason is required/, flash[:alert])
        assert_empty @client.updated
        assert_empty @graph.send_mails
      end

      test "reject stamps the reason and notified time and sends the rejection via Graph" do
        expense = pending_expense(id: "recRej", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        sign_in @user

        patch :reject, params: { id: "recRej", rejection_reason: "Missing receipt" }

        _table, _id, fields = @client.updated.sole
        assert_equal "Rejected", fields[EXP[:status]]
        assert_equal "Missing receipt", fields[EXP[:rejection_reason]]
        assert fields[EXP[:rejection_notified]].present?

        mail = @graph.send_mails.sole
        assert_equal "reimbursements@bedlamfringe.co.uk", mail[:mailbox]
        assert_equal [ "pat@example.com" ], mail[:to]
        assert_match(/not approved/, mail[:subject])
        assert_match "Missing receipt", mail[:html]
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
        assert_empty @graph.send_mails
      end

      test "a Graph send failure still rejects the expense but leaves it unnotified" do
        expense = pending_expense(id: "recRej", payment_reference: "PROPS PAT")
        rebuild_store(expenses: [ expense ])
        @graph.fail_send = true
        sign_in @user

        patch :reject, params: { id: "recRej", rejection_reason: "Missing receipt" }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        _table, _id, fields = @client.updated.sole
        assert_equal "Rejected", fields[EXP[:status]]
        assert_not fields.key?(EXP[:rejection_notified]), "a failed send must not claim notified"
      end

      test "reject works from the Approved tab too" do
        approved = airtable_expense_record(id: "recApprovedRej", payee_id: "recPer1", budget_id: "recBud1",
                                           status: "Approved", auto_number: 9)
        rebuild_store(expenses: [ approved ])
        sign_in @user

        patch :reject, params: { id: "recApprovedRej", rejection_reason: "Duplicate claim" }

        _table, _id, fields = @client.updated.sole
        assert_equal "Rejected", fields[EXP[:status]]
      end

      test "a stale reject against an already-Submitted expense is refused" do
        submitted = airtable_expense_record(id: "recSubmittedRej", payee_id: "recPer1", budget_id: "recBud1",
                                            status: "Submitted", auto_number: 9)
        rebuild_store(expenses: [ submitted ])
        sign_in @user

        patch :reject, params: { id: "recSubmittedRej", rejection_reason: "Too late" }

        assert_match(/can no longer be rejected/, flash[:alert])
        assert_empty @client.updated
        assert_empty @graph.send_mails
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
