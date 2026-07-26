require "test_helper"

module Admin
  module Reimbursements
    class ReviewControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers
      include ActiveJob::TestHelper

      MC = ::Reimbursements::ModulusCheck

      FakeChecker = ReimbursementsTestHelpers::FakeModulusChecker

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)

        @person = create_reimbursements_person(name: "Pat Producer", email: "pat@example.com",
                                               sort_code: "08-99-99", account_number: "66374958")
        @no_bank_person = create_reimbursements_person(name: "Nora NoBank", email: "nora@example.com")
        @budget = create_reimbursements_budget(name: "Props", nominal_code: "4000")

        @checker = FakeChecker.new("66374958" => MC::VALID)
        ReviewController.checker_builder = -> { @checker }

        # Rejection emails now go through the Graph notifier; inject a real
        # Notifier over a recording FakeGraphClient so tests assert the send
        # (mailbox / recipient / subject / body) rather than an enqueued mailer.
        @graph = FakeGraphClient.new
        ReviewController.notifier_builder =
          ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre, graph: @graph) }
      end

      teardown do
        BaseController.store_builder = -> { ::Reimbursements.build_store }
        ReviewController.checker_builder = -> { MC.default_checker }
        ReviewController.notifier_builder =
          ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre) }
      end

      # Consented by default (the ordinary case for a claim submitted through the
      # portal since the consent question shipped); the AI-check gate tests pass
      # false/nil explicitly.
      def pending_expense(person: @person, budget: @budget, **attrs)
        create_reimbursements_expense(person: person, budget: budget,
                                      **{ ai_processing_consent: true }.merge(attrs))
      end

      def attach_image_receipt(expense, tag)
        attach_test_receipt(expense, filename: "receipt#{tag}.jpg", content_type: "image/jpeg",
                            bytes: "JPEG#{tag}")
      end

      # --- Auth gating -----------------------------------------------------

      test "requires sign-in" do
        get :index
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        sign_in users(:committee)
        get :index
        assert_response :forbidden
      end

      test "the producer portal permission alone does not grant finance access" do
        other = users(:member_with_phone_number)
        grant_producer_permission(other)
        sign_in other

        get :index

        assert_response :forbidden
      end

      # --- Index: partition, flags, AI kick --------------------------------

      test "partitions pending into ready and needs-attention, and lists approved separately" do
        # Distinct amounts so these two don't incidentally look like duplicates
        # of each other (same payee — see #find_duplicate_submissions).
        ready = pending_expense(amount: BigDecimal("111"))
        attention = pending_expense(amount: BigDecimal("222"), amount_excl_vat: nil) # missing excl VAT
        approved = pending_expense(status: ::Reimbursements::Status::APPROVED)
        sign_in @user

        get :index

        assert_response :success
        assert_equal [ ready.record_id ], assigns(:ready).map(&:record_id)
        assert_equal [ attention.record_id ], assigns(:attention).map(&:record_id)
        assert_equal [ approved.record_id ], assigns(:approved).map(&:record_id)
      end

      test "the current tab is marked aria-current, the other is not" do
        pending_expense
        sign_in @user

        get :index, params: { tab: "approved" }

        assert_select "a[aria-current=page]", text: /Approved/
        assert_select "a[aria-current=page]", text: /Pending/, count: 0
      end

      # --- CSV export --------------------------------------------------------

      test "index CSV export answers a text/csv download named for today" do
        pending_expense
        sign_in @user

        get :index, format: :csv

        assert_csv_download("expenses")
      end

      test "index CSV export exports the queue with the shared Expenses columns" do
        pending_expense(auto_number: 1, description: "Fake blood")
        sign_in @user

        get :index, format: :csv

        rows = CSV.parse(response.body)
        assert_equal ::Reimbursements::Exports::Expenses::HEADERS, rows.first
        assert_equal 2, rows.size, "header + the one pending expense"
        assert_equal %w[1 Pending], rows[1].values_at(0, 1)
        assert_equal "Pat Producer", rows[1][2]
        assert_equal "Fake blood", rows[1][6]
      end

      test "index CSV export follows the tab, exporting only that tab's expenses" do
        pending_expense(auto_number: 1, description: "Still pending")
        pending_expense(auto_number: 2, description: "Already approved",
                        status: ::Reimbursements::Status::APPROVED)
        sign_in @user

        get :index, params: { tab: "approved" }, format: :csv

        rows = CSV.parse(response.body)
        assert_equal 2, rows.size, "header + the one approved expense"
        assert_includes response.body, "Already approved"
        assert_not_includes response.body, "Still pending"
      end

      test "index offers a Download CSV link carrying the current tab" do
        pending_expense
        sign_in @user

        get :index, params: { tab: "approved" }

        assert_includes response.body, "Download CSV"
        # Rails sorts the query string, so: /review?format=csv&tab=approved
        assert_includes response.body, "/admin/reimbursements/review?format=csv&amp;tab=approved"
      end

      test "renders the payee-override warning" do
        pending_expense(payee_name_override: "Acme Lighting Ltd",
                        sort_code_override: "20-00-00",
                        account_number_override: "66374958")
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "Direct payment to"
        assert_includes response.body, "Acme Lighting Ltd"
      end

      test "renders receipts in a fancybox gallery keyed per expense, still managed inline" do
        a = pending_expense(receipt: false)
        b = pending_expense(receipt: false)
        attach_image_receipt(a, "A")
        attach_image_receipt(b, "B")
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, 'data-controller="fancybox receipt-viewer"'
        # Each card gets its own fancybox group so the lightbox pages within one expense.
        assert_includes response.body, "data-fancybox=\"receipts-#{a.record_id}\""
        assert_includes response.body, "data-fancybox=\"receipts-#{b.record_id}\""
        assert_includes response.body, a.receipts.sole.url
        # Reviewers can still attach/detach receipts inline (per-tab review routes).
        assert_match(/Remove this receipt/, response.body)
        assert_includes response.body, admin_reimbursements_review_receipts_path(a.record_id, tab: "pending")
      end

      # --- In-page receipt viewer ------------------------------------------

      # Each card carries its own viewer pane, closed until a thumbnail is
      # clicked, so reviewing a queue never sends the operator to a new tab.
      test "each card renders a receipt strip wired to its own closed viewer pane" do
        a = pending_expense(receipt: false)
        b = pending_expense(receipt: false)
        attach_test_receipt(a, filename: "invoice-a.pdf")
        attach_test_receipt(b, filename: "invoice-b.pdf")
        sign_in @user

        get :index

        assert_response :success
        [ a, b ].each do |expense|
          pane_id = "receipt-pane-#{expense.record_id}"
          assert_includes response.body, "id=\"#{pane_id}\""
          assert_includes response.body, "aria-controls=\"#{pane_id}\""
          assert_includes response.body, "aria-label=\"Receipt viewer for expense ##{expense.auto_number}\""
        end
        # A thumbnail is a real button with its own accessible name, not a link.
        assert_includes response.body, 'aria-label="View receipt 1 of 1, invoice-a.pdf"'
        assert_includes response.body, 'data-action="receipt-viewer#show"'
        # Nothing navigates away from the queue any more.
        assert_no_match(/<a[^>]+target="_blank"[^>]*>\s*<span[^>]*>\s*<i class="fa-solid fa-file-lines/,
                        response.body)
      end

      # Twenty pending claims must not pull twenty PDFs on page load, so the pane's
      # <iframe> ships with data-src only and the controller assigns src on open.
      test "a queue of claims fetches no receipt documents on page load" do
        3.times { |i| attach_test_receipt(pending_expense(receipt: false), filename: "r#{i}.pdf") }
        sign_in @user

        get :index

        assert_response :success
        frames = response.body.scan(/<iframe[^>]*>/)
        assert_equal 3, frames.size, "one frame per claim"
        frames.each do |frame|
          assert_match(/data-src="/, frame)
          assert_no_match(/\ssrc="/, frame, "the frame must not be loaded until it is opened")
        end
      end

      test "renders a duplicate-submission warning" do
        first = pending_expense(amount: BigDecimal("12.5"))
        second = pending_expense(amount: BigDecimal("12.5"))
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "Possible duplicate of"
        # A possible duplicate is otherwise clean (bank details, budget, amount
        # all fine) but must still land in Attention, not Ready — approving both
        # in two clicks would double-pay the same claim.
        assert_equal [ first.record_id, second.record_id ].sort,
                     assigns(:attention).map(&:record_id).sort
        assert_empty assigns(:ready)
      end

      test "kicks an AI check for each unchecked pending expense only" do
        unchecked = pending_expense
        pending_expense(amount: BigDecimal("99"), ai_check_status: "pass") # already checked
        sign_in @user

        assert_enqueued_with(job: ::Reimbursements::AiCheckJob, args: [ unchecked.record_id ]) do
          get :index
        end
        assert_enqueued_jobs 1, only: ::Reimbursements::AiCheckJob
      end

      test "re-kicks an AI check for an expense stuck on an error verdict" do
        errored = pending_expense(ai_check_status: "error")
        sign_in @user

        assert_enqueued_with(job: ::Reimbursements::AiCheckJob, args: [ errored.record_id ]) do
          get :index
        end
      end

      # The consent the receipt form asks for covers this check too, so opening
      # the queue must not send a declined submitter's receipt to Google —
      # otherwise picking "No" is hollow, since Review kicks the checks off
      # automatically on load.
      test "kicks no AI check for a claim whose submitter declined AI processing" do
        pending_expense(ai_processing_consent: false)
        sign_in @user

        get :index

        assert_response :success
        assert_no_enqueued_jobs only: ::Reimbursements::AiCheckJob
      end

      # Absent consent is a refusal: pre-existing claims and email-in claims were
      # never asked, so they are reviewed by hand.
      test "kicks no AI check for a claim with no consent recorded" do
        pending_expense(ai_processing_consent: nil)
        sign_in @user

        get :index

        assert_response :success
        assert_no_enqueued_jobs only: ::Reimbursements::AiCheckJob
      end

      test "still kicks an AI check for the consented claim in a mixed queue" do
        consented = pending_expense
        pending_expense(amount: BigDecimal("77"), ai_processing_consent: false)
        pending_expense(amount: BigDecimal("88"), ai_processing_consent: nil)
        sign_in @user

        assert_enqueued_with(job: ::Reimbursements::AiCheckJob, args: [ consented.record_id ]) do
          get :index
        end
        assert_enqueued_jobs 1, only: ::Reimbursements::AiCheckJob
      end

      # A claim that will never be checked must say so plainly, instead of
      # promising a verdict that can never arrive ("AI check running…").
      test "the card explains a declined claim was not checked, not that a check is running" do
        pending_expense(ai_processing_consent: false)
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "did not consent to AI processing"
        assert_not_includes response.body, "AI check running"
      end

      test "the card distinguishes a claim nobody was asked from an outright refusal" do
        pending_expense(ai_processing_consent: nil)
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, "no consent to AI processing recorded"
        assert_not_includes response.body, "AI check running"
      end

      # Neither state is a failure or a flag: a declined claim must not read as
      # suspicious, so no warning/danger styling and no AI badge pill.
      test "the not-checked explanation is neutral, not a failed or flagged verdict" do
        pending_expense(ai_processing_consent: false)
        sign_in @user

        get :index

        assert_not_includes response.body, "AI check flagged this"
        assert_not_includes response.body, "AI check could not run"
        assert_not_includes response.body, "AI: Fail"
        assert_not_includes response.body, "AI: Error"
      end

      # Decision: verdicts already written stay. A claim checked before the gate
      # existed still shows its verdict, however its consent column reads.
      test "a verdict written before the gate existed is still shown" do
        pending_expense(ai_processing_consent: nil, ai_check_status: "fail",
                        ai_comment: "Amount doesn't match.")
        sign_in @user

        get :index

        assert_includes response.body, "AI: Fail"
        assert_includes response.body, "Amount doesn&#39;t match."
        assert_not_includes response.body, "no consent to AI processing recorded"
      end

      test "a consented but unchecked claim still shows the running placeholder" do
        pending_expense
        sign_in @user

        get :index

        assert_includes response.body, "AI check running"
      end

      # --- Bulk actions ----------------------------------------------------

      test "the pending tab exposes bulk-select checkboxes and a bulk toolbar" do
        a = pending_expense
        sign_in @user

        get :index

        assert_response :success
        assert_select "[data-controller~=?]", "bulk-review"
        assert_select "input[data-bulk-review-target=selectAll]"
        assert_select "form#bulk-review-form[action=?]",
                      admin_reimbursements_bulk_approve_review_path(tab: "pending")
        assert_select "input[type=checkbox][name=?][value=?][form=bulk-review-form]",
                      "expense_ids[]", a.record_id
        assert_select "input[data-bulk-review-target=rejectButton][data-turbo-confirm*=?]",
                      "email each producer"
      end

      test "a flagged card's Approve confirms with its reasons; a clean card's doesn't" do
        clean = pending_expense
        # No receipts -> "no receipt" attention reason (advisory-only, so the
        # server never blocks it — this confirm is the only safety net).
        flagged = pending_expense(receipt: false)
        sign_in @user

        get :index

        assert_response :success
        flagged_form = css_select("form[action*='#{admin_reimbursements_approve_review_path(flagged.record_id)}']").first
        assert_includes flagged_form["data-turbo-confirm"], "no receipt"
        assert_includes flagged_form["data-turbo-confirm"], "Approve anyway?"
        clean_form = css_select("form[action*='#{admin_reimbursements_approve_review_path(clean.record_id)}']").first
        assert_nil clean_form["data-turbo-confirm"], "clean cards keep one-click approval"
        # The bulk toolbar's flagged-count confirm reads these markers.
        assert_select "input#select_#{flagged.record_id}[data-flagged=true]"
        assert_select "input#select_#{clean.record_id}[data-flagged=false]"
      end

      test "a blocking card disables Approve instead of offering a doomed 'anyway'" do
        # No bank details -> blocking (approve_expense refuses it), so the
        # button can never succeed and must be disabled, not a misleading
        # "Approve anyway?".
        blocked = pending_expense(person: @no_bank_person)
        sign_in @user

        get :index

        assert_response :success
        assert_select "button[aria-label*='Approve #'][disabled]"
        assert_select "form[action*='#{admin_reimbursements_approve_review_path(blocked.record_id)}']", 0
      end

      test "approve refuses a budget present but with a blank record id (blank nominal-code guard)" do
        # attention_summary flags this as blocking; approve_expense must agree,
        # or it would write a blank nominal code into the BACS spreadsheet. A
        # blank-record_id budget can't exist as a DB row, so build the value
        # object unpersisted (record_id pinned blank) and serve it through a
        # DatabaseStore whose writes are recorded.
        blank_budget = ::Reimbursements::Budget.new(name: "Ghost", nominal_code: "")
        blank_budget.define_singleton_method(:record_id) { "" }
        person = ::Reimbursements::Person.new(name: "Pat", email: "p@x.co")
        person.build_payment_details(sort_code: "08-99-99", account_number: "66374958")
        expense = ::Reimbursements::Expense.new(
          auto_number: 5, status: ::Reimbursements::Status::PENDING, person: person,
          amount: BigDecimal("10"), amount_excl_vat: BigDecimal("8"), budget: blank_budget
        )
        expense.instance_variable_set(:@receipts, [])
        expense.define_singleton_method(:record_id) { "recBlankBud" }
        store = ::Reimbursements::DatabaseStore.new
        updates = []
        store.define_singleton_method(:find_expense!) { |_id| expense }
        store.define_singleton_method(:update_expense!) { |*args| updates << args }
        BaseController.store_builder = -> { store }
        sign_in @user

        patch :approve, params: { id: "recBlankBud" }

        assert_empty updates, "must not approve an expense with a blank-record_id budget"
        assert_match(/without a budget/i, flash[:alert])
      end

      test "bulk approve advances every selected pending expense" do
        a = pending_expense
        b = pending_expense
        sign_in @user

        patch :bulk_approve, params: { expense_ids: [ a.record_id, b.record_id ] }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_equal ::Reimbursements::Status::APPROVED, a.reload.status
        assert_equal ::Reimbursements::Status::APPROVED, b.reload.status
        assert_match(/2 approved/, flash[:notice])
      end

      test "bulk approve skips an expense that lacks bank details" do
        ok = pending_expense
        no_bank = pending_expense(person: @no_bank_person)
        sign_in @user

        patch :bulk_approve, params: { expense_ids: [ ok.record_id, no_bank.record_id ] }

        assert_equal ::Reimbursements::Status::APPROVED, ok.reload.status
        assert_equal ::Reimbursements::Status::PENDING, no_bank.reload.status
        assert_match(/1 approved/, flash[:notice])
        assert_match(/1 skipped \(missing bank details, budget, or amount\)/, flash[:notice])
      end

      test "bulk approve with nothing selected writes nothing and reports it" do
        a = pending_expense
        sign_in @user

        patch :bulk_approve, params: { expense_ids: [] }

        assert_match(/Select at least one/, flash[:alert])
        assert_equal ::Reimbursements::Status::PENDING, a.reload.status, "nothing was written"
      end

      test "bulk reject rejects each selected expense and emails each producer" do
        a = pending_expense
        b = pending_expense
        sign_in @user

        patch :bulk_reject, params: { expense_ids: [ a.record_id, b.record_id ],
                                      rejection_reason: "Duplicate batch" }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        [ a, b ].each do |expense|
          expense.reload
          assert_equal ::Reimbursements::Status::REJECTED, expense.status
          assert_equal "Duplicate batch", expense.rejection_reason
        end
        assert_equal 2, @graph.send_mails.size
        assert_match(/2 rejected/, flash[:notice])
      end

      test "bulk reject requires a reason and writes nothing" do
        a = pending_expense
        sign_in @user

        patch :bulk_reject, params: { expense_ids: [ a.record_id ], rejection_reason: "  " }

        assert_match(/reason is required/, flash[:alert])
        assert_equal ::Reimbursements::Status::PENDING, a.reload.status, "nothing was written"
        assert_empty @graph.send_mails
      end

      test "bulk actions ignore a stale selection of a non-pending expense" do
        approved = pending_expense(status: ::Reimbursements::Status::APPROVED)
        untouched = approved.reload.updated_at
        sign_in @user

        patch :bulk_approve, params: { expense_ids: [ approved.record_id ] }

        assert_equal untouched, approved.reload.updated_at, "nothing was written"
        assert_match(/Select at least one/, flash[:alert])
      end

      # --- Save ------------------------------------------------------------

      test "save writes the edited fields" do
        expense = pending_expense
        sign_in @user

        patch :save, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "16.67",
                               description: "Updated blood", payment_reference: "NEWREF",
                               nominal_code_override: "4100", budget_record_id: @budget.record_id }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        expense.reload
        assert_equal BigDecimal("20"), expense.amount
        assert_equal BigDecimal("16.67"), expense.amount_excl_vat
        assert_equal "Updated blood", expense.description
        assert_equal "NEWREF", expense.payment_reference
        assert_equal "4100", expense.nominal_code_override
      end

      # A rejected edit must write NOTHING — no field of the record, not just
      # the one the validation tripped on. Compares every column against the
      # pre-request copy (updated_at excluded: the seed helper's receipt
      # attach touches it after the in-memory copy was loaded).
      def assert_no_write(expense)
        fresh = ::Reimbursements::Expense.find(expense.id)
        assert_equal expense.attributes.except("updated_at"), fresh.attributes.except("updated_at"),
                     "nothing may be written on a rejected edit"
      end

      test "save rejects a budget_record_id that doesn't resolve to a real budget" do
        expense = pending_expense
        sign_in @user

        patch :save, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "16.67",
                               description: "x", payment_reference: "y", budget_record_id: "999999999" }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/budget no longer exists/i, flash[:alert])
        assert_no_write(expense)
      end

      test "save leaves excl VAT untouched when zero is submitted" do
        expense = pending_expense
        sign_in @user

        patch :save, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "0",
                               description: "x", payment_reference: "y", budget_record_id: @budget.record_id }

        assert_equal BigDecimal("10.42"), expense.reload.amount_excl_vat
      end

      test "save rejects a negative amount and writes nothing" do
        expense = pending_expense
        sign_in @user

        patch :save, params: { id: expense.record_id, amount: "-5", amount_excl_vat: "16.67",
                               description: "x", budget_record_id: @budget.record_id }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/valid amount/i, flash[:alert])
        assert_no_write(expense)
      end

      test "save rejects a non-numeric amount and writes nothing" do
        expense = pending_expense
        sign_in @user

        patch :save, params: { id: expense.record_id, amount: "abc", amount_excl_vat: "16.67",
                               description: "x", budget_record_id: @budget.record_id }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/valid amount/i, flash[:alert])
        assert_no_write(expense)
      end

      test "save rejects a negative excl-VAT amount and writes nothing" do
        expense = pending_expense
        sign_in @user

        patch :save, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "-1",
                               description: "x", budget_record_id: @budget.record_id }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/excl. VAT/i, flash[:alert])
        assert_no_write(expense)
      end

      test "save rejects an excl-VAT amount greater than the total and writes nothing" do
        expense = pending_expense
        sign_in @user

        patch :save, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "25.00",
                               description: "x", budget_record_id: @budget.record_id }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/can't be more than the total/i, flash[:alert])
        assert_no_write(expense)
      end

      # --- Approve ---------------------------------------------------------

      test "approve auto-fills a payment reference when blank and marks approved" do
        expense = pending_expense(payment_reference: "")
        sign_in @user

        patch :approve, params: { id: expense.record_id }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        expense.reload
        assert_equal ::Reimbursements::Status::APPROVED, expense.status
        assert_equal "Props", expense.payment_reference
      end

      test "approve keeps an existing payment reference" do
        expense = pending_expense(payment_reference: "KEEPME")
        sign_in @user

        patch :approve, params: { id: expense.record_id }

        expense.reload
        assert_equal ::Reimbursements::Status::APPROVED, expense.status
        assert_equal "KEEPME", expense.payment_reference
      end

      # --- Owner-endorsement gate (Phase E3) -------------------------------

      def owner_person
        @owner_person ||= create_reimbursements_person(name: "Olga Owner", email: "olga@example.com",
                                                       sort_code: "08-99-99", account_number: "66374958")
      end

      def owned_budget
        @owned_budget ||= create_reimbursements_budget(name: "Owned", nominal_code: "4100",
                                                       owners: [ owner_person ])
      end

      # Submitted by @person (who has bank details), charged to a budget owned
      # by owner_person — so the submitter isn't an owner and the gate applies.
      def gated_expense
        @gated_expense ||= pending_expense(budget: owned_budget, payment_reference: "OWNED PAT")
      end

      def endorse_gated_expense!
        ::Reimbursements::OwnerEndorsement.create!(
          expense_record_id: gated_expense.record_id, budget_record_id: owned_budget.record_id,
          endorsed_by_person_id: owner_person.record_id, endorsed_amount: BigDecimal("12.5"),
          endorsed_at: Time.current
        )
      end

      test "approve refuses a claim awaiting a budget owner's endorsement" do
        gated_expense
        sign_in @user

        patch :approve, params: { id: gated_expense.record_id }

        assert_match(/needs a budget owner's endorsement/i, flash[:alert])
        assert_equal ::Reimbursements::Status::PENDING, gated_expense.reload.status, "nothing was written"
      end

      test "approve succeeds once an owner has endorsed the claim" do
        # gated_expense carries create_reimbursements_expense's default amount (12.5).
        endorse_gated_expense!
        sign_in @user

        patch :approve, params: { id: gated_expense.record_id }

        assert_equal ::Reimbursements::Status::APPROVED, gated_expense.reload.status
      end

      test "approve auto-bypasses a claim the budget owner submitted themselves" do
        own = pending_expense(person: owner_person, budget: owned_budget, payment_reference: "OWNED")
        sign_in @user

        patch :approve, params: { id: own.record_id }

        assert_equal ::Reimbursements::Status::APPROVED, own.reload.status
      end

      test "override_approve records the finance override and approves" do
        gated_expense
        sign_in @user

        assert_difference -> { ::Reimbursements::OwnerEndorsement.count }, 1 do
          patch :override_approve, params: { id: gated_expense.record_id }
        end

        endorsement = ::Reimbursements::OwnerEndorsement.for_expense(gated_expense.record_id).first
        assert endorsement.finance_override?
        assert_equal @user.id, endorsement.overridden_by_id
        assert_equal BigDecimal("12.5"), endorsement.endorsed_amount, "override snapshots the amount"
        assert_equal ::Reimbursements::Status::APPROVED, gated_expense.reload.status
        assert_match(/overridden/i, flash[:notice])
      end

      test "override_approve writes no override row and reports the hard block when one remains" do
        # A gated claim that ALSO lacks bank details: overriding must surface the
        # bank problem and NOT write a gate-satisfying row (else a later plain
        # approve would sail past the owner gate we'd have silently satisfied).
        no_bank = pending_expense(person: @no_bank_person, budget: owned_budget,
                                  payment_reference: "OWNED")
        sign_in @user

        assert_no_difference -> { ::Reimbursements::OwnerEndorsement.count } do
          patch :override_approve, params: { id: no_bank.record_id }
        end
        assert_match(/without bank details/, flash[:alert])
        assert_equal ::Reimbursements::Status::PENDING, no_bank.reload.status, "nothing was written"
      end

      test "override_approve truncates an over-long note instead of 500ing" do
        gated_expense
        sign_in @user

        assert_nothing_raised do
          patch :override_approve, params: { id: gated_expense.record_id, override_note: "x" * 500 }
        end
        assert_equal 255, ::Reimbursements::OwnerEndorsement.for_expense(gated_expense.record_id).first.note.length
      end

      test "the review queue sorts a gated claim into attention with an override button" do
        gated_expense
        sign_in @user

        get :index

        assert_response :success
        assert_includes assigns(:attention).map(&:record_id), gated_expense.record_id
        assert_select "form[action=?]",
                      admin_reimbursements_override_approve_review_path(gated_expense.record_id, tab: "pending")
      end

      test "bulk approve skips a claim awaiting owner endorsement" do
        clean = pending_expense
        gated_expense
        sign_in @user

        patch :bulk_approve, params: { expense_ids: [ clean.record_id, gated_expense.record_id ] }

        # Only the clean (ownerless-budget) claim advanced; the gated one skipped.
        assert_equal ::Reimbursements::Status::APPROVED, clean.reload.status
        assert_equal ::Reimbursements::Status::PENDING, gated_expense.reload.status
        # ...and the summary names the owner-gate reason, not "missing bank/budget/amount".
        assert_match(/1 approved/, flash[:notice])
        assert_match(/1 awaiting owner sign-off/, flash[:notice])
      end

      test "the review card shows who endorsed a covered claim" do
        endorse_gated_expense!
        sign_in @user

        get :index

        assert_includes assigns(:ready).map(&:record_id), gated_expense.record_id,
                        "an endorsed claim is ready, not attention"
        assert_includes response.body, "Endorsed by Olga Owner"
      end

      test "editing a covered claim's amount re-opens the gate and says so" do
        endorse_gated_expense!
        sign_in @user

        patch :save, params: { id: gated_expense.record_id, amount: "999.00", amount_excl_vat: "999.00",
                               description: "x", payment_reference: "OWNED PAT",
                               budget_record_id: owned_budget.record_id }

        assert_match(/needs a fresh owner sign-off/i, flash[:notice])
      end

      test "override_approve stores the finance override note" do
        gated_expense
        sign_in @user

        patch :override_approve, params: { id: gated_expense.record_id,
                                           override_note: "Owner has no portal account" }

        assert_equal "Owner has no portal account",
                     ::Reimbursements::OwnerEndorsement.for_expense(gated_expense.record_id).first.note
      end

      test "approve is blocked without effective bank details" do
        expense = pending_expense(person: @no_bank_person)
        sign_in @user

        patch :approve, params: { id: expense.record_id }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/without bank details/, flash[:alert])
        assert_equal ::Reimbursements::Status::PENDING, expense.reload.status, "nothing was written"
      end

      test "approve is blocked without a linked budget" do
        expense = pending_expense(budget: nil)
        sign_in @user

        patch :approve, params: { id: expense.record_id }

        assert_match(/without a budget linked/, flash[:alert])
        assert_equal ::Reimbursements::Status::PENDING, expense.reload.status, "nothing was written"
      end

      test "approve is blocked without a non-zero excl-VAT amount" do
        expense = pending_expense(amount_excl_vat: 0)
        sign_in @user

        patch :approve, params: { id: expense.record_id }

        assert_match(/without an amount excluding VAT/, flash[:alert])
        assert_equal ::Reimbursements::Status::PENDING, expense.reload.status, "nothing was written"
      end

      test "a stale approve against an already-Approved expense is a no-op, not a re-approve" do
        already = pending_expense(status: ::Reimbursements::Status::APPROVED, auto_number: 9)
        untouched = already.reload.updated_at
        sign_in @user

        patch :approve, params: { id: already.record_id }

        assert_match(/no longer Pending/, flash[:alert])
        assert_equal untouched, already.reload.updated_at, "nothing was written"
      end

      # --- Reject ----------------------------------------------------------

      test "the reject form asks for confirmation before emailing the producer" do
        expense = pending_expense(auto_number: 42)
        sign_in @user

        get :index

        assert_response :success
        assert_select "form[action=?][data-turbo-confirm*=?]",
                      admin_reimbursements_reject_review_path(expense.record_id, tab: "pending"),
                      "Reject #42 and email the producer"
      end

      test "reject requires a reason" do
        expense = pending_expense
        sign_in @user

        patch :reject, params: { id: expense.record_id, rejection_reason: "  " }

        assert_match(/reason is required/, flash[:alert])
        assert_equal ::Reimbursements::Status::PENDING, expense.reload.status, "nothing was written"
        assert_empty @graph.send_mails
      end

      test "reject stamps the reason and notified time and sends the rejection via Graph" do
        expense = pending_expense
        sign_in @user

        patch :reject, params: { id: expense.record_id, rejection_reason: "Missing receipt" }

        expense.reload
        assert_equal ::Reimbursements::Status::REJECTED, expense.status
        assert_equal "Missing receipt", expense.rejection_reason
        assert expense.rejection_notified.present?

        mail = @graph.send_mails.sole
        assert_equal "reimbursements@bedlamfringe.co.uk", mail[:mailbox]
        assert_equal [ "pat@example.com" ], mail[:to]
        assert_match(/not approved/, mail[:subject])
        assert_match "Missing receipt", mail[:html]
      end

      test "reject without a payee email still rejects but does not stamp notified or email" do
        no_email_person = create_reimbursements_person(name: "Norman NoEmail", email: nil)
        expense = pending_expense(person: no_email_person)
        sign_in @user

        patch :reject, params: { id: expense.record_id, rejection_reason: "Bad" }

        expense.reload
        assert_equal ::Reimbursements::Status::REJECTED, expense.status
        assert_nil expense.rejection_notified
        assert_empty @graph.send_mails
      end

      test "a Graph send failure still rejects the expense but leaves it unnotified" do
        expense = pending_expense
        @graph.fail_send = true
        sign_in @user

        patch :reject, params: { id: expense.record_id, rejection_reason: "Missing receipt" }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        expense.reload
        assert_equal ::Reimbursements::Status::REJECTED, expense.status
        assert_nil expense.rejection_notified, "a failed send must not claim notified"
      end

      test "reject works from the Approved tab too" do
        approved = pending_expense(status: ::Reimbursements::Status::APPROVED, auto_number: 9)
        sign_in @user

        patch :reject, params: { id: approved.record_id, rejection_reason: "Duplicate claim" }

        assert_equal ::Reimbursements::Status::REJECTED, approved.reload.status
      end

      test "a stale reject against an already-Submitted expense is refused" do
        submitted = pending_expense(status: ::Reimbursements::Status::SUBMITTED, auto_number: 9)
        sign_in @user

        patch :reject, params: { id: submitted.record_id, rejection_reason: "Too late" }

        assert_match(/can no longer be rejected/, flash[:alert])
        assert_equal ::Reimbursements::Status::SUBMITTED, submitted.reload.status, "nothing was written"
        assert_empty @graph.send_mails
      end

      test "acting on an unknown expense 404s" do
        sign_in @user

        patch :approve, params: { id: "999999999" }

        assert_response :not_found
      end

      # --- Save-then-decide (unsaved-edits dialog) --------------------------
      # The review card's Save form is separate from the Approve/Reject forms, so
      # an edit-then-decide would otherwise drop the edits. When the operator
      # picks "Save Changes" in the client dialog, the decision request carries
      # the edited fields plus save_changes=1 and the server persists them FIRST,
      # in the same request, so the decision acts on the saved values.

      test "approve with save_changes persists the edited fields, then approves" do
        expense = pending_expense(description: "Old", payment_reference: "")
        sign_in @user

        patch :approve, params: { id: expense.record_id, save_changes: "1",
                                  amount: "20.00", amount_excl_vat: "16.67",
                                  description: "Edited before approve", payment_reference: "REF1",
                                  nominal_code_override: "4100", budget_record_id: @budget.record_id }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        expense.reload
        assert_equal ::Reimbursements::Status::APPROVED, expense.status
        assert_equal BigDecimal("20"), expense.amount
        assert_equal BigDecimal("16.67"), expense.amount_excl_vat
        assert_equal "Edited before approve", expense.description
        assert_equal "REF1", expense.payment_reference
        assert_equal "4100", expense.nominal_code_override
      end

      test "approve with save_changes aborts the decision when the edit fails validation" do
        expense = pending_expense(description: "Old")
        sign_in @user

        patch :approve, params: { id: expense.record_id, save_changes: "1",
                                  amount: "-5", amount_excl_vat: "16.67",
                                  description: "Should not persist", budget_record_id: @budget.record_id }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/valid amount/i, flash[:alert])
        expense.reload
        assert_equal ::Reimbursements::Status::PENDING, expense.status, "decision aborted"
        assert_equal "Old", expense.description, "no edit persisted on an aborted decision"
      end

      test "reject with save_changes persists the edited fields, then rejects" do
        expense = pending_expense(description: "Old")
        sign_in @user

        patch :reject, params: { id: expense.record_id, save_changes: "1",
                                 rejection_reason: "Wrong budget",
                                 amount: "20.00", amount_excl_vat: "16.67",
                                 description: "Edited before reject", budget_record_id: @budget.record_id }

        expense.reload
        assert_equal ::Reimbursements::Status::REJECTED, expense.status
        assert_equal BigDecimal("20"), expense.amount
        assert_equal "Edited before reject", expense.description
        assert_equal "Wrong budget", expense.rejection_reason
      end

      test "reject with save_changes aborts the decision when the edit fails validation" do
        expense = pending_expense(description: "Old")
        sign_in @user

        patch :reject, params: { id: expense.record_id, save_changes: "1",
                                 rejection_reason: "Wrong budget",
                                 amount: "abc", amount_excl_vat: "16.67",
                                 description: "Should not persist", budget_record_id: @budget.record_id }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/valid amount/i, flash[:alert])
        expense.reload
        assert_equal ::Reimbursements::Status::PENDING, expense.status, "decision aborted"
        assert_equal "Old", expense.description, "no edit persisted on an aborted decision"
        assert_empty @graph.send_mails, "no rejection email fired on an aborted decision"
      end

      test "override_approve with save_changes persists the edited fields, then overrides" do
        gated_expense
        sign_in @user

        patch :override_approve, params: { id: gated_expense.record_id, save_changes: "1",
                                           amount: "30.00", amount_excl_vat: "25.00",
                                           description: "Edited before override",
                                           payment_reference: "OWNED PAT",
                                           budget_record_id: owned_budget.record_id }

        gated_expense.reload
        assert_equal ::Reimbursements::Status::APPROVED, gated_expense.status
        assert_equal BigDecimal("30"), gated_expense.amount
        assert_equal "Edited before override", gated_expense.description
      end

      test "override_approve with save_changes aborts the decision when the edit fails validation" do
        gated_expense
        sign_in @user

        assert_no_difference -> { ::Reimbursements::OwnerEndorsement.count } do
          patch :override_approve, params: { id: gated_expense.record_id, save_changes: "1",
                                             amount: "-5", amount_excl_vat: "1",
                                             description: "Should not persist",
                                             budget_record_id: owned_budget.record_id }
        end

        assert_match(/valid amount/i, flash[:alert])
        gated_expense.reload
        assert_equal ::Reimbursements::Status::PENDING, gated_expense.status, "decision aborted"
        assert_equal "Fake blood", gated_expense.description, "no edit persisted on an aborted decision"
      end

      # The decision must act on the SAVED values, not the pre-edit ones. Returning
      # the stale expense from save_edits_before_decision passes every test above
      # (they only check the row afterwards), while the owner-endorsement gate would
      # be evaluated against superseded terms: an owner-endorsed £12.50 claim edited
      # to £3,000 through Save Changes would be approved against the £12.50
      # sign-off, defeating the re-endorsement rule entirely.
      test "approve with save_changes re-opens the owner gate when the edit changes the amount" do
        endorse_gated_expense! # covers amount 12.5 on owned_budget
        sign_in @user

        patch :approve, params: { id: gated_expense.record_id, save_changes: "1",
                                  amount: "3000.00", amount_excl_vat: "2500.00",
                                  description: "Edited up before approve",
                                  payment_reference: "OWNED PAT",
                                  budget_record_id: owned_budget.record_id }

        assert_match(/needs a budget owner's endorsement/i, flash[:alert],
                     "the decision must see the SAVED amount, not the endorsed one")
        gated_expense.reload
        assert_equal ::Reimbursements::Status::PENDING, gated_expense.status
        # The save still stands — only the decision is blocked, so the operator can
        # see what they changed and chase a fresh sign-off.
        assert_equal BigDecimal("3000"), gated_expense.amount
      end

      # The mirror case: an edit that leaves the endorsed terms alone still approves,
      # so re-opening the gate isn't just "any save_changes blocks".
      test "approve with save_changes still approves when the edit leaves the endorsed terms alone" do
        endorse_gated_expense!
        sign_in @user

        patch :approve, params: { id: gated_expense.record_id, save_changes: "1",
                                  amount: "12.50", amount_excl_vat: "10.42",
                                  description: "Wording fixed only",
                                  payment_reference: "OWNED PAT",
                                  budget_record_id: owned_budget.record_id }

        gated_expense.reload
        assert_equal ::Reimbursements::Status::APPROVED, gated_expense.status
        assert_equal "Wording fixed only", gated_expense.description
      end

      test "override_approve with save_changes snapshots the SAVED amount on the endorsement" do
        gated_expense
        sign_in @user

        patch :override_approve, params: { id: gated_expense.record_id, save_changes: "1",
                                           amount: "3000.00", amount_excl_vat: "2500.00",
                                           description: "Edited up before override",
                                           payment_reference: "OWNED PAT",
                                           budget_record_id: owned_budget.record_id }

        endorsement = ::Reimbursements::OwnerEndorsement.for_expense(gated_expense.record_id).first
        assert_equal BigDecimal("3000"), endorsement.endorsed_amount,
                     "the override must snapshot the amount it actually approved"
        assert_equal ::Reimbursements::Status::APPROVED, gated_expense.reload.status
      end

      # Moving the claim to a DIFFERENT owned budget through Save Changes re-opens
      # the gate too — the endorsement was given for the old budget's line.
      test "approve with save_changes re-opens the owner gate when the edit changes the budget" do
        endorse_gated_expense!
        other_owned = create_reimbursements_budget(name: "Owned Too", nominal_code: "4200",
                                                   owners: [ owner_person ])
        sign_in @user

        patch :approve, params: { id: gated_expense.record_id, save_changes: "1",
                                  amount: "12.50", amount_excl_vat: "10.42",
                                  description: "Moved to another budget",
                                  payment_reference: "OWNED PAT",
                                  budget_record_id: other_owned.record_id }

        assert_match(/needs a budget owner's endorsement/i, flash[:alert])
        gated_expense.reload
        assert_equal ::Reimbursements::Status::PENDING, gated_expense.status
        assert_equal other_owned.id, gated_expense.budget_id, "the move still saved"
      end

      test "a plain approve without save_changes still approves without touching the edit fields" do
        # Backwards-compatibility: the pristine-form path posts no edit params.
        expense = pending_expense(description: "Original", payment_reference: "KEEP")
        sign_in @user

        patch :approve, params: { id: expense.record_id }

        expense.reload
        assert_equal ::Reimbursements::Status::APPROVED, expense.status
        assert_equal "Original", expense.description, "no save happened without save_changes"
      end

      # --- Unsaved-edits dialog wiring (rendered markup) -------------------

      test "the review card wires the unsaved-edits guard on its decision controls" do
        expense = pending_expense
        sign_in @user

        get :index

        assert_response :success
        assert_select "div[data-controller~=?]", "review-decision"
        assert_select "dialog[data-review-decision-target=dialog]"
        assert_select "form[data-review-decision-target=editForm]"
        # Approve (button_to) and Reject (submit_tag) both carry the click guard
        # plus a verb the dialog title reads.
        assert_select "[data-action*=?][data-decision-verb=approving]", "review-decision#guard"
        assert_select "[data-action*=?][data-decision-verb=rejecting]", "review-decision#guard"
        # All three ways out of the dialog.
        assert_select "dialog button", text: "Cancel"
        assert_select "dialog button", text: "Save Changes"
        assert_select "dialog button", text: "Discard Changes"
        # The heading is the dialog's accessible name, and the native close event
        # (Escape included) is wired so a dismissed dialog forgets its decision.
        title_id = "unsaved-edits-title-#{expense.record_id}"
        assert_select "dialog[aria-labelledby=?][data-action*=?]", title_id, "close->review-decision#closed"
        assert_select "h2##{title_id}[data-review-decision-target=title]"
      end

      test "the review card wires the guard on the owner-gate override button too" do
        gated_expense
        sign_in @user

        get :index

        assert_response :success
        assert_select "[data-action*=?][data-decision-verb=approving]", "review-decision#guard"
      end
    end
  end
end
