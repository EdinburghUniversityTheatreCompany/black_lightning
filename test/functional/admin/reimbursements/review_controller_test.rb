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
          ->(mailbox:) { ::Reimbursements::Notifier.new(mailbox: mailbox, graph: @graph) }
      end

      teardown do
        BaseController.store_builder = -> { ::Reimbursements.build_store }
        ReviewController.checker_builder = -> { MC.default_checker }
        ReviewController.notifier_builder =
          ->(mailbox:) { ::Reimbursements::Notifier.new(mailbox: mailbox) }
      end

      def pending_expense(person: @person, budget: @budget, **attrs)
        create_reimbursements_expense(person: person, budget: budget, **attrs)
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
        assert_includes response.body, 'data-controller="fancybox"'
        # Each card gets its own fancybox group so the lightbox pages within one expense.
        assert_includes response.body, "data-fancybox=\"receipts-#{a.record_id}\""
        assert_includes response.body, "data-fancybox=\"receipts-#{b.record_id}\""
        assert_includes response.body, a.receipts.sole.url
        # Reviewers can still attach/detach receipts inline (per-tab review routes).
        assert_match(/Remove this receipt/, response.body)
        assert_includes response.body, admin_reimbursements_review_receipts_path(a.record_id, tab: "pending")
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
        # blank-record_id budget can't exist as a DB row, so serve the Airtable
        # PORO shape through a DatabaseStore whose writes are recorded.
        blank_budget = ::Reimbursements::Airtable::Budget.new(record_id: "", name: "Ghost", nominal_code: "")
        expense = ::Reimbursements::Airtable::Expense.new(
          record_id: "recBlankBud", auto_number: 5, status: ::Reimbursements::Status::PENDING,
          person: ::Reimbursements::Airtable::Person.new(record_id: "recPer1", name: "Pat", email: "p@x.co",
                                               sort_code: "08-99-99", account_number: "66374958"),
          amount: BigDecimal("10"), amount_excl_vat: BigDecimal("8"), budget: blank_budget
        )
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

      test "save rejects a budget_record_id that doesn't resolve to a real budget" do
        expense = pending_expense
        sign_in @user

        patch :save, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "16.67",
                               description: "x", payment_reference: "y", budget_record_id: "999999999" }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/budget no longer exists/i, flash[:alert])
        assert_equal "Fake blood", expense.reload.description, "nothing was written"
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
        assert_equal BigDecimal("12.5"), expense.reload.amount, "nothing was written"
      end

      test "save rejects a non-numeric amount and writes nothing" do
        expense = pending_expense
        sign_in @user

        patch :save, params: { id: expense.record_id, amount: "abc", amount_excl_vat: "16.67",
                               description: "x", budget_record_id: @budget.record_id }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/valid amount/i, flash[:alert])
        assert_equal BigDecimal("12.5"), expense.reload.amount, "nothing was written"
      end

      test "save rejects a negative excl-VAT amount and writes nothing" do
        expense = pending_expense
        sign_in @user

        patch :save, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "-1",
                               description: "x", budget_record_id: @budget.record_id }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/excl. VAT/i, flash[:alert])
        assert_equal BigDecimal("12.5"), expense.reload.amount, "nothing was written"
      end

      test "save rejects an excl-VAT amount greater than the total and writes nothing" do
        expense = pending_expense
        sign_in @user

        patch :save, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "25.00",
                               description: "x", budget_record_id: @budget.record_id }

        assert_redirected_to admin_reimbursements_review_path(tab: nil)
        assert_match(/can't be more than the total/i, flash[:alert])
        assert_equal BigDecimal("12.5"), expense.reload.amount, "nothing was written"
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
    end
  end
end
