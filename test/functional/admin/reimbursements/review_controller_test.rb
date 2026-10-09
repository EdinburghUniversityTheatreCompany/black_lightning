require "test_helper"

module Admin
  module Reimbursements
    class ReviewControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      MC = ::Reimbursements::ModulusCheck

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)

        @person = create_reimbursements_person(name: "Pat Producer", email: "pat@example.com",
                                               sort_code: "08-99-99", account_number: "66374958")
        @no_bank_person = create_reimbursements_person(name: "Nora NoBank", email: "nora@example.com")
        @budget = create_reimbursements_budget(name: "Props", nominal_code: "4000")

        @checker = FakeModulusChecker.new("66374958" => MC::VALID)
        ReviewController.checker_builder = -> { @checker }

        # A real Notifier over a recording FakeGraphClient, so tests assert the send.
        @graph = FakeGraphClient.new
        ReviewController.notifier_builder =
          ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre, graph: @graph) }
      end

      teardown do
        BaseController.store_builder = BaseController::DEFAULT_STORE_BUILDER
        ReviewController.checker_builder = -> { MC.default_checker }
        ReviewController.notifier_builder =
          ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre) }
      end

      # The queue redirect, ignoring the ?focus= anchor, which has tests of its own.
      def assert_redirected_to_review(**query)
        target = URI.parse(@response.redirect_url)
        rest = Rack::Utils.parse_nested_query(target.query.to_s).except("focus")
        query_string = rest.any? ? "?#{rest.to_query}" : ""
        assert_equal admin_reimbursements_review_path(**query), "#{target.path}#{query_string}"
      end

      # Where the last redirect came back to: ?focus= and the fragment must agree.
      def redirect_anchor
        target = URI.parse(@response.redirect_url)
        focus = Rack::Utils.parse_nested_query(target.query.to_s)["focus"]
        if focus.nil?
          assert_nil target.fragment, "no ?focus= means no fragment either"
        else
          assert_equal focus, target.fragment,
                       "the ?focus= parameter and the fragment must name the same card"
        end
        focus
      end

      def pending_expense(person: @person, budget: @budget, **attrs)
        create_reimbursements_expense(person: person, budget: budget, **attrs)
      end

      def attach_image_receipt(expense, tag)
        attach_test_receipt(expense, filename: "receipt#{tag}.jpg", content_type: "image/jpeg",
                            bytes: "JPEG#{tag}")
      end

      test "each card's budget select is a Tom Select" do
        expense = create_reimbursements_expense(person: @person, budget: @budget, status: "Pending")
        sign_in @user

        get :index

        assert_select "select#budget_record_id_#{expense.record_id}.simple-select2:not([class*=border])"
      end

      test "partitions pending into ready and needs-attention, and lists approved separately" do
        # Distinct amounts, or the two read as duplicates.
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

      test "the current tab is marked aria-current, the others are not" do
        pending_expense
        sign_in @user

        get :index, params: { tab: "approved" }

        assert_select "a[aria-current=page]", text: /Approved/
        assert_select "a[aria-current=page]", text: /To approve/, count: 0
        assert_select "a[aria-current=page]", text: /Awaiting owner/, count: 0
      end

      test "no tab, an unknown tab and the old tab=pending land on the finance queue" do
        gated_expense
        sign_in @user

        [ nil, "nonsense", "pending" ].each do |tab|
          get :index, params: { tab: tab }.compact
          assert_equal "to_approve", assigns(:tab), tab.inspect
        end
        assert_select "a[aria-current=page]", text: /To approve/
      end

      test "a gated claim is on the awaiting-owner tab, not in the finance queue" do
        gated_expense
        ready = pending_expense(auto_number: 77) # on the ownerless @budget
        sign_in @user

        get :index, params: { tab: "awaiting_owner" }

        assert_equal [ gated_expense.record_id ], assigns(:awaiting_owner).map(&:record_id)
        assert_equal [ ready.record_id ], assigns(:to_approve).map(&:record_id)
        assert_not_includes assigns(:attention).map(&:record_id), gated_expense.record_id
        assert_not_includes assigns(:ready).map(&:record_id), gated_expense.record_id
      end

      test "the awaiting-owner tab still offers the finance override" do
        gated_expense
        sign_in @user

        get :index, params: { tab: "awaiting_owner" }

        assert_response :success
        assert_select "form[action=?]",
                      admin_reimbursements_override_approve_review_path(gated_expense.record_id,
                                                                       tab: "awaiting_owner")
      end

      test "the awaiting-owner tab CSV exports only the gated claims" do
        gated_expense
        pending_expense(auto_number: 79, description: "Not gated")
        sign_in @user

        get :index, params: { tab: "awaiting_owner" }, format: :csv

        rows = CSV.parse(response.body)
        assert_equal 2, rows.size, "header + the one gated claim"
        assert_not_includes response.body, "Not gated"
      end

      test "index CSV export exports the queue with the shared Expenses columns" do
        pending_expense(auto_number: 1, description: "Fake blood")
        sign_in @user

        get :index, format: :csv

        assert_csv_download("expenses")
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

      # How long the producer has waited is the first question asked of a claim.
      test "each card states the date the claim was submitted, on both tabs" do
        pending_expense(auto_number: 7, submitted_at: Time.utc(2026, 5, 1, 9))
        pending_expense(auto_number: 8, status: ::Reimbursements::Status::APPROVED,
                        submitted_at: Time.utc(2026, 4, 2, 9))
        sign_in @user

        { nil => "2026-05-01", "approved" => "2026-04-02" }.each do |tab, day|
          get :index, params: { tab: tab }.compact
          assert_select "span", text: "Submitted #{day}"
        end
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

      test "each card renders its receipts in its own viewer pane and fancybox group, managed inline" do
        a = pending_expense(receipt: false)
        b = pending_expense(receipt: false)
        attach_image_receipt(a, "A")
        attach_image_receipt(b, "B")
        sign_in @user

        get :index

        assert_response :success
        assert_includes response.body, 'data-controller="fancybox receipt-viewer"'
        [ a, b ].each do |expense|
          # One fancybox group per card, so the lightbox pages within one expense.
          assert_includes response.body, "data-fancybox=\"receipts-#{expense.record_id}\""
          pane_id = "receipt-pane-#{expense.record_id}"
          assert_includes response.body, "id=\"#{pane_id}\""
          assert_includes response.body, "aria-controls=\"#{pane_id}\""
          assert_includes response.body, "aria-label=\"Receipt viewer for expense ##{expense.auto_number}\""
        end
        assert_includes response.body, a.receipts.sole.url
        assert_match(/Remove this receipt/, response.body)
        assert_includes response.body, admin_reimbursements_review_receipts_path(a.record_id, tab: "to_approve")
        # A thumbnail is a real button with its own accessible name, not a link.
        assert_includes response.body, 'aria-label="View receipt 1 of 1, receiptA.jpg"'
        assert_includes response.body, 'data-action="receipt-viewer#show"'
        # Nothing navigates away from the queue.
        assert_no_match(/<a[^>]+target="_blank"[^>]*>\s*<span[^>]*>\s*<i class="fa-solid fa-file-lines/,
                        response.body)
      end

      # The pane's <iframe> ships data-src only; the controller sets src on open.
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
        # Otherwise clean, but approving both would double-pay.
        assert_equal [ first.record_id, second.record_id ].sort,
                     assigns(:attention).map(&:record_id).sort
        assert_empty assigns(:ready)
      end

      test "the to-approve tab exposes bulk-select checkboxes and a bulk toolbar" do
        a = pending_expense
        sign_in @user

        get :index

        assert_response :success
        assert_select "[data-controller~=?]", "bulk-review"
        assert_select "input[data-bulk-review-target=selectAll]"
        assert_select "form#bulk-review-form[action=?]",
                      admin_reimbursements_bulk_approve_review_path(tab: "to_approve")
        assert_select "input[type=checkbox][name=?][value=?][form=bulk-review-form]",
                      "expense_ids[]", a.record_id
        assert_select "input[data-bulk-review-target=rejectButton][data-turbo-confirm*=?]",
                      "email each producer"
      end

      test "a flagged card's Approve confirms with its reasons; a clean card's doesn't" do
        clean = pending_expense
        # No receipt is advisory, so this confirm is the only guard.
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
        blocked = pending_expense(person: @no_bank_person)
        sign_in @user

        get :index

        assert_response :success
        assert_select "button[aria-label*='Approve #'][disabled]"
        assert_select "form[action*='#{admin_reimbursements_approve_review_path(blocked.record_id)}']", 0
      end

      test "bulk approve advances every selected pending expense" do
        a = pending_expense
        b = pending_expense
        sign_in @user

        patch :bulk_approve, params: { expense_ids: [ a.record_id, b.record_id ] }

        assert_redirected_to_review
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

      test "bulk reject rejects each selected expense and emails each producer" do
        a = pending_expense
        b = pending_expense
        sign_in @user

        patch :bulk_reject, params: { expense_ids: [ a.record_id, b.record_id ],
                                      rejection_reason: "Duplicate batch" }

        assert_redirected_to_review
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

      # AR casts "£1,200" to 0, so the parsed value is what must be written.
      test "save writes the edited fields, parsing currency-formatted amounts" do
        expense = pending_expense
        sign_in @user

        patch :save, params: { id: expense.record_id, amount: "£1,200.50", amount_excl_vat: "1,000",
                               description: "Updated blood", payment_reference: "NEWREF",
                               nominal_code_override: "4100", budget_record_id: @budget.record_id }

        assert_redirected_to_review
        expense.reload
        assert_equal BigDecimal("1200.50"), expense.amount
        assert_equal BigDecimal("1000"), expense.amount_excl_vat
        assert_equal "Updated blood", expense.description
        assert_equal "NEWREF", expense.payment_reference
        assert_equal "4100", expense.nominal_code_override
      end

      # Every column unchanged. updated_at is excluded: the seed helper's receipt
      # attach touches it after the copy was loaded.
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

        assert_redirected_to_review
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

      test "save rejects a non-numeric amount and writes nothing" do
        expense = pending_expense
        sign_in @user

        patch :save, params: { id: expense.record_id, amount: "abc", amount_excl_vat: "16.67",
                               description: "x", budget_record_id: @budget.record_id }

        assert_redirected_to_review
        assert_match(/valid amount/i, flash[:alert])
        assert_no_write(expense)
      end

      test "approve auto-fills a payment reference when blank and marks approved" do
        expense = pending_expense(payment_reference: "")
        sign_in @user

        patch :approve, params: { id: expense.record_id }

        assert_redirected_to_review
        expense.reload
        assert_equal ::Reimbursements::Status::APPROVED, expense.status
        assert_equal "Props", expense.payment_reference
      end

      # Three shows' lines are all called "Marketing", so the reference names the show.
      test "the auto-filled reference names the show when the budget is in an area" do
        @budget.update!(area: create_reimbursements_area(name: "Cogito"))
        expense = pending_expense(payment_reference: "")
        sign_in @user

        patch :approve, params: { id: expense.record_id }

        assert_equal "Cogito Props", expense.reload.payment_reference
      end

      test "approve keeps an existing payment reference and saves no edits" do
        expense = pending_expense(description: "Original", payment_reference: "KEEPME")
        sign_in @user

        patch :approve, params: { id: expense.record_id }

        expense.reload
        assert_equal ::Reimbursements::Status::APPROVED, expense.status
        assert_equal "KEEPME", expense.payment_reference
        assert_equal "Original", expense.description, "no save without save_changes"
      end

      test "a card carries an id the redirect can anchor to" do
        expense = pending_expense
        sign_in @user

        get :index

        assert_select "div##{"expense-#{expense.record_id}"}"
      end

      test "saving a card comes back to that card" do
        expense = pending_expense
        sign_in @user

        patch :save, params: { id: expense.record_id, amount: "20.00", amount_excl_vat: "18.00",
                               description: "x", payment_reference: "REF",
                               budget_record_id: @budget.record_id }

        assert_equal "expense-#{expense.record_id}", redirect_anchor
      end

      test "approving comes back to the next card that was below it" do
        # Distinct amounts, or the two read as duplicates.
        first = pending_expense(amount: BigDecimal("111"), amount_excl_vat: BigDecimal("100"))
        second = pending_expense(amount: BigDecimal("222"), amount_excl_vat: BigDecimal("200"))
        sign_in @user

        patch :approve, params: { id: first.record_id }

        assert_equal ::Reimbursements::Status::APPROVED, first.reload.status
        assert_equal "expense-#{second.record_id}", redirect_anchor,
                     "the approved card has left this tab, so anchor where the eye already was"
      end

      test "approving the last card on the tab anchors nowhere" do
        only = pending_expense(amount: BigDecimal("333"), amount_excl_vat: BigDecimal("300"))
        sign_in @user

        patch :approve, params: { id: only.record_id }

        assert_nil redirect_anchor, "nothing below it survived, so fall back to the top of the list"
      end

      test "a bulk action anchors nowhere: it acted on no single card" do
        expense = pending_expense
        sign_in @user

        patch :bulk_approve, params: { expense_ids: [ expense.record_id ] }

        assert_nil redirect_anchor
      end

      def owner_person
        @owner_person ||= create_reimbursements_person(name: "Olga Owner", email: "olga@example.com",
                                                       sort_code: "08-99-99", account_number: "66374958")
      end

      def owned_budget
        @owned_budget ||= create_reimbursements_budget(name: "Owned", nominal_code: "4100",
                                                       owners: [ owner_person ])
      end

      # Submitted by @person on owner_person's budget, so the gate applies.
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

      test "override_approve records the finance override and approves" do
        gated_expense
        sign_in @user

        assert_difference -> { ::Reimbursements::OwnerEndorsement.count }, 1 do
          patch :override_approve, params: { id: gated_expense.record_id,
                                             override_note: "Owner has no portal account" }
        end

        endorsement = ::Reimbursements::OwnerEndorsement.for_expense(gated_expense.record_id).first
        assert endorsement.finance_override?
        assert_equal @user.id, endorsement.overridden_by_id
        assert_equal "Owner has no portal account", endorsement.note
        assert_equal BigDecimal("12.5"), endorsement.endorsed_amount, "override snapshots the amount"
        assert_equal ::Reimbursements::Status::APPROVED, gated_expense.reload.status
        assert_match(/overridden/i, flash[:notice])
      end

      test "override_approve keeps an owner's endorsement that landed after the page loaded" do
        endorse_gated_expense!
        sign_in @user

        patch :override_approve, params: { id: gated_expense.record_id, override_note: "Stale page" }

        endorsement = ::Reimbursements::OwnerEndorsement.for_expense(gated_expense.record_id).first
        assert_equal owner_person.record_id, endorsement.endorsed_by_person_id
        assert_nil endorsement.overridden_by_id
        assert_equal ::Reimbursements::Status::APPROVED, gated_expense.reload.status
        assert_no_match(/overridden/i, flash[:notice])
      end

      def second_gated_expense
        @second_gated_expense ||= pending_expense(budget: owned_budget, payment_reference: "OWNED 2")
      end

      test "bulk override records who overrode it and why, and approves every ticked claim" do
        claims = [ gated_expense, second_gated_expense ]
        sign_in @user

        assert_difference -> { ::Reimbursements::OwnerEndorsement.count }, 2 do
          patch :bulk_override_approve, params: { expense_ids: claims.map(&:record_id),
                                                  override_note: "Owner has left" }
        end

        claims.each do |claim|
          assert_equal ::Reimbursements::Status::APPROVED, claim.reload.status
          endorsement = ::Reimbursements::OwnerEndorsement.for_expense(claim.record_id).first
          assert endorsement.finance_override?
          assert_equal @user.id, endorsement.overridden_by_id
          assert_equal "Owner has left", endorsement.note
        end
        assert_equal "2 approved with sign-off overridden.", flash[:notice]
      end

      test "bulk override refuses without a note and writes nothing" do
        gated_expense
        sign_in @user

        assert_no_difference -> { ::Reimbursements::OwnerEndorsement.count } do
          patch :bulk_override_approve, params: {
            expense_ids: [ gated_expense.record_id ], override_note: "  "
          }
        end

        assert_match(/only record of the decision/, flash[:alert])
        assert_equal ::Reimbursements::Status::PENDING, gated_expense.reload.status
      end

      test "bulk override refuses with nothing ticked" do
        sign_in @user

        patch :bulk_override_approve, params: { override_note: "Owner has left" }

        assert_match(/Select at least one claim/, flash[:alert])
      end

      test "bulk override skips a claim with a hard block and writes no row for it" do
        gated_expense
        no_bank = pending_expense(person: @no_bank_person, budget: owned_budget,
                                  payment_reference: "OWNED NB")
        sign_in @user

        assert_difference -> { ::Reimbursements::OwnerEndorsement.count }, 1 do
          patch :bulk_override_approve, params: {
            expense_ids: [ gated_expense.record_id, no_bank.record_id ],
            override_note: "No owner holds a portal account"
          }
        end

        assert_equal ::Reimbursements::Status::APPROVED, gated_expense.reload.status
        assert_equal ::Reimbursements::Status::PENDING, no_bank.reload.status
        assert_empty ::Reimbursements::OwnerEndorsement.for_expense(no_bank.record_id)
        assert_match(/1 skipped/, flash[:notice])
      end

      test "the Awaiting owner tab offers the bulk override and no bulk approve" do
        gated_expense
        sign_in @user

        get :index, params: { tab: "awaiting_owner" }

        assert_response :success
        assert_select "form[action*=?]", "bulk_override_approve"
        assert_select "form[action*=?]", "bulk_approve", count: 0
      end

      test "override_approve writes no override row and reports the hard block when one remains" do
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

        patch :override_approve, params: { id: gated_expense.record_id, override_note: "x" * 500 }

        assert_equal 255, ::Reimbursements::OwnerEndorsement.for_expense(gated_expense.record_id).first.note.length
      end

      test "bulk approve skips a claim awaiting owner endorsement" do
        clean = pending_expense
        gated_expense
        sign_in @user

        patch :bulk_approve, params: { expense_ids: [ clean.record_id, gated_expense.record_id ] }

        assert_equal ::Reimbursements::Status::APPROVED, clean.reload.status
        assert_equal ::Reimbursements::Status::PENDING, gated_expense.reload.status
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

      test "the Approved tab keeps the 'Owner sign-off overridden' pill" do
        gated_expense
        sign_in @user
        patch :override_approve, params: { id: gated_expense.record_id }

        get :index, params: { tab: "approved" }

        assert_response :success
        assert_includes assigns(:approved).map(&:record_id), gated_expense.record_id
        assert_match(/Owner sign-off overridden/, response.body)
      end

      test "editing a covered claim's amount re-opens the gate and says so" do
        endorse_gated_expense!
        sign_in @user

        patch :save, params: { id: gated_expense.record_id, amount: "999.00", amount_excl_vat: "999.00",
                               description: "x", payment_reference: "OWNED PAT",
                               budget_record_id: owned_budget.record_id }

        assert_match(/needs a fresh owner sign-off/i, flash[:notice])
      end

      test "a gated claim blocked on something else does not promise a finance override" do
        pending_expense(person: @no_bank_person, budget: owned_budget, payment_reference: "OWNED")
        sign_in @user

        get :index, params: { tab: "awaiting_owner" }

        assert_response :success
        assert_no_match(/use the finance override below/, response.body)
        assert_match(/Fix the blocking problem above first/, response.body)
      end

      test "a gated claim with nothing else wrong still offers the override" do
        gated_expense
        sign_in @user

        get :index, params: { tab: "awaiting_owner" }

        assert_match(/use the finance override below/, response.body)
      end

      test "the awaiting-owner card links each owner's email and states the wait" do
        gated_expense.update!(submitted_at: 6.days.ago)
        sign_in @user

        get :index, params: { tab: "awaiting_owner" }

        assert_select "a[href=?]", "mailto:olga@example.com", text: "Olga Owner"
        assert_match(/Waiting 6 days\./, response.body)
        assert_match(/reminded on each run day/, response.body)
        assert_match(/no address is never emailed/, response.body)
      end

      test "the awaiting-owner card says a claim was submitted today" do
        gated_expense.update!(submitted_at: Time.current)
        sign_in @user

        get :index, params: { tab: "awaiting_owner" }

        assert_match(/Submitted today\./, response.body)
      end

      def international_expense(**attrs)
        pending_expense(
          payment_method: ::Reimbursements::Expense::PAYMENT_METHOD_INTERNATIONAL,
          foreign_amount: BigDecimal("266.69"),
          foreign_currency: ::Reimbursements::Expense::CURRENCY_EUR,
          iban_override: "DE89370400440532013000", bic_override: "DEUTDEFF500",
          **attrs
        )
      end

      test "the card masks a third party's IBAN like a UK account, full value only behind the reveal" do
        international_expense(payee_name_override: "Studio Bühne")
        sign_in @user

        get :index

        assert_select "[data-bank-details-target='value'][data-revealed=?]", "DE89 3704 0044 0532 0130 00",
                      text: "****3000"
        assert_no_match(/>[^<]*DE89/, response.body, "the IBAN must not be rendered as visible text")
        assert_includes response.body, "DEUTDEFF500"
      end

      # A People record has no IBAN field, so pointing there is a dead end.
      test "an international claim with no IBAN or BIC sends finance to the claim's override" do
        expense = international_expense(iban_override: nil, bic_override: nil, person: @no_bank_person)
        sign_in @user

        get :index

        assert_match(/No IBAN and BIC on this claim/, response.body)
        assert_select "a[href=?]", edit_admin_reimbursements_expense_edit_path(expense.record_id),
                      text: "payee override"
        assert_select "a", text: /People record/, count: 0
      end

      test "approve accepts an international claim with an IBAN and both amounts" do
        expense = international_expense
        sign_in @user

        patch :approve, params: { id: expense.record_id }

        assert_equal ::Reimbursements::Status::APPROVED, expense.reload.status
      end

      test "approve refuses each hard block and writes nothing" do
        sign_in @user
        [
          [ -> { pending_expense(person: @no_bank_person) }, /without bank details/ ],
          [ -> { international_expense(iban_override: nil, bic_override: nil, person: @no_bank_person) },
            /without bank details/ ],
          [ -> { international_expense(foreign_amount: nil) }, /without the amount in EUR/ ],
          [ -> { international_expense(foreign_amount: nil, foreign_currency: "USD") }, /without the amount in USD/ ],
          # Budget rollups are GBP, so approving without one books the claim at nothing.
          [ -> { international_expense(amount: nil) }, /without a GBP amount/ ],
          [ -> { pending_expense(budget: nil) }, /without a budget linked/ ],
          [ -> { pending_expense(amount_excl_vat: 0) }, /without an amount excluding VAT/ ]
        ].each do |build, alert|
          expense = build.call

          patch :approve, params: { id: expense.record_id }

          assert_match alert, flash[:alert], alert.inspect
          assert_equal ::Reimbursements::Status::PENDING, expense.reload.status, "nothing was written"
        end
      end

      test "a stale approve against an already-Approved expense is a no-op, not a re-approve" do
        already = pending_expense(status: ::Reimbursements::Status::APPROVED, auto_number: 9)
        untouched = already.reload.updated_at
        sign_in @user

        patch :approve, params: { id: already.record_id }

        assert_match(/no longer Pending/, flash[:alert])
        assert_equal untouched, already.reload.updated_at, "nothing was written"
      end

      test "the reject form asks for confirmation before emailing the producer" do
        expense = pending_expense(auto_number: 42)
        sign_in @user

        get :index

        assert_response :success
        assert_select "form[action=?][data-turbo-confirm*=?]",
                      admin_reimbursements_reject_review_path(expense.record_id, tab: "to_approve"),
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
        assert_match "Hi Pat,", mail[:html], "Pat Producer is greeted by first name only"
        assert_includes mail[:html], "https://www.example.com/admin/reimbursements/expenses/#{expense.record_id}"
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

        assert_redirected_to_review
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

      test "approve with save_changes persists the edited fields, then approves" do
        expense = pending_expense(description: "Old", payment_reference: "")
        sign_in @user

        patch :approve, params: { id: expense.record_id, save_changes: "1",
                                  amount: "20.00", amount_excl_vat: "16.67",
                                  description: "Edited before approve", payment_reference: "REF1",
                                  nominal_code_override: "4100", budget_record_id: @budget.record_id }

        assert_redirected_to_review
        expense.reload
        assert_equal ::Reimbursements::Status::APPROVED, expense.status
        assert_equal BigDecimal("20"), expense.amount
        assert_equal BigDecimal("16.67"), expense.amount_excl_vat
        assert_equal "Edited before approve", expense.description
        assert_equal "REF1", expense.payment_reference
        assert_equal "4100", expense.nominal_code_override
      end

      test "a decision with save_changes is aborted when the edit fails validation" do
        sign_in @user

        { approve: {}, reject: { rejection_reason: "Wrong budget" }, override_approve: {} }.each do |action, extra|
          claim = action == :override_approve ? gated_expense : pending_expense

          patch action, params: { id: claim.record_id, save_changes: "1", amount: "-5", amount_excl_vat: "1",
                                  description: "Should not persist", budget_record_id: claim.budget.record_id,
                                  **extra }

          assert_match(/valid amount/i, flash[:alert], action)
          claim.reload
          assert_equal ::Reimbursements::Status::PENDING, claim.status, "#{action}: decision aborted"
          assert_equal "Fake blood", claim.description, "#{action}: no edit persisted"
        end
        assert_empty @graph.send_mails, "no rejection email on an aborted decision"
        assert_equal 0, ::Reimbursements::OwnerEndorsement.count, "no override row on an aborted decision"
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

      test "override_approve with save_changes saves the edits, then overrides on the SAVED amount" do
        gated_expense
        sign_in @user

        patch :override_approve, params: { id: gated_expense.record_id, save_changes: "1",
                                           amount: "3000.00", amount_excl_vat: "2500.00",
                                           description: "Edited before override",
                                           payment_reference: "OWNED PAT",
                                           budget_record_id: owned_budget.record_id }

        gated_expense.reload
        assert_equal ::Reimbursements::Status::APPROVED, gated_expense.status
        assert_equal BigDecimal("3000"), gated_expense.amount
        assert_equal "Edited before override", gated_expense.description
        endorsement = ::Reimbursements::OwnerEndorsement.for_expense(gated_expense.record_id).first
        assert_equal BigDecimal("3000"), endorsement.endorsed_amount,
                     "the override must snapshot the amount it actually approved"
      end

      # The decision must act on the SAVED values: a £12.50 endorsement must not
      # approve the claim edited to £3,000.
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
        assert_match(/needs a fresh owner sign-off/i, flash[:alert], "names this edit as the cause")
        gated_expense.reload
        assert_equal ::Reimbursements::Status::PENDING, gated_expense.status
        # The save stands; only the decision is blocked.
        assert_equal BigDecimal("3000"), gated_expense.amount
      end

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

      # --- The chosen cost centre survives every click --------------------

      test "the tab links keep the selected cost centre" do
        termtime = create_second_reimbursements_cost_centre
        expense = pending_expense
        sign_in @user

        get :index, params: { cost_centre: termtime.key }

        %w[awaiting_owner to_approve approved].each do |tab|
          assert_select "a[href=?]", admin_reimbursements_review_path(tab: tab, cost_centre: termtime.key)
        end
        assert_select "form[action=?]", admin_reimbursements_approve_review_path(
          expense.record_id, tab: "to_approve", cost_centre: termtime.key
        )
      end

      test "an approval comes back to the same cost centre" do
        termtime = create_second_reimbursements_cost_centre
        expense = pending_expense
        sign_in @user

        patch :approve, params: { id: expense.record_id, tab: "to_approve", cost_centre: termtime.key }

        assert_redirected_to_review(tab: "to_approve", cost_centre: termtime.key)
      end

      # An explicit All (cost_centre=) is a choice: a page that drops it lets the
      # sidebar put the operator's home centre back on the next click.
      test "the tab links and card actions keep an explicit All" do
        create_second_reimbursements_cost_centre
        expense = pending_expense
        sign_in @user

        get :index, params: { cost_centre: "" }

        assert_select "a[href=?]", admin_reimbursements_review_path(tab: "approved", cost_centre: "")
        assert_select "form[action=?]", admin_reimbursements_approve_review_path(
          expense.record_id, tab: "to_approve", cost_centre: ""
        )
      end

      test "an approval from an explicit All comes back to All" do
        create_second_reimbursements_cost_centre
        expense = pending_expense
        sign_in @user

        patch :approve, params: { id: expense.record_id, tab: "to_approve", cost_centre: "" }

        assert_redirected_to_review(tab: "to_approve", cost_centre: "")
      end

      test "the review card wires the unsaved-edits guard on its decision controls" do
        expense = pending_expense
        sign_in @user

        get :index

        assert_response :success
        assert_select "div[data-controller~=?]", "review-decision"
        assert_select "dialog[data-review-decision-target=dialog]"
        assert_select "form[data-review-decision-target=editForm]"
        # Both decisions carry the guard and the verb the dialog title reads.
        assert_select "[data-action*=?][data-decision-verb=approving]", "review-decision#guard"
        assert_select "[data-action*=?][data-decision-verb=rejecting]", "review-decision#guard"
        assert_select "dialog button", text: "Cancel"
        assert_select "dialog button", text: "Save Changes"
        assert_select "dialog button", text: "Discard Changes"
        # Escape fires the native close event, which must forget the decision.
        title_id = "unsaved-edits-title-#{expense.record_id}"
        assert_select "dialog[aria-labelledby=?][data-action*=?]", title_id, "close->review-decision#closed"
        assert_select "h2##{title_id}[data-review-decision-target=title]"
      end
    end
  end
end
