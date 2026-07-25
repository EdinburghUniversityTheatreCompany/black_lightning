require "application_system_test_case"

module Admin
  module Reimbursements
    # Browser tests for the three finance-surface JS interactions that render
    # tests can't cover: the accessible needs-attention popover (open on click /
    # close on Escape), the Fancybox receipts lightbox, and the Review page's
    # live-AI-verdict Turbo Stream subscription.
    #
    # Data is served by the DatabaseStore from real seeded rows; a fake modulus
    # checker keeps the tests off the gitignored Pay.UK rule files. Capybara
    # serves the app in-process, so setting the class attributes here is visible
    # to the request thread.
    class FinanceJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      # Always-VALID modulus verdict, so a fully-detailed payee never trips a
      # "needs attention" bank-details reason and "no receipt" is the only flag.
      class FakeChecker
        def check(_sort_code, _account_number)
          ::Reimbursements::ModulusCheck::VALID
        end
      end

      setup do
        grant_finance_permission(users(:member))
        @person = create_reimbursements_person(name: "Pat Producer", email: "pat@example.com",
                                               sort_code: "08-99-99", account_number: "66374958")
        @budget = create_reimbursements_budget(name: "Props", nominal_code: "4000")
        @checker = FakeChecker.new
        ExpenseEditsController.checker_builder = -> { @checker }
        ReviewController.checker_builder = -> { @checker }
        login_as users(:member)
      end

      teardown do
        ExpenseEditsController.checker_builder = -> { ::Reimbursements::ModulusCheck.default_checker }
        ReviewController.checker_builder = -> { ::Reimbursements::ModulusCheck.default_checker }
      end

      def seed_expense(status:, receipt: true, **attrs)
        create_reimbursements_expense(person: @person, budget: @budget, status: status,
                                      receipt: receipt, **attrs)
      end

      # A PDF poppler can actually render, so the first-page preview these tests
      # assert on is a real one. The suite's default receipt bytes are a stub
      # header that raises ActiveStorage::PreviewError at generation time.
      def renderable_pdf_bytes
        file_fixture("renderable_receipt.pdf").binread
      end

      def renderable_png_bytes
        file_fixture("renderable_receipt.png").binread
      end

      # The src ATTRIBUTE of every frame in a pane, in strip order. nil means
      # that receipt has never been fetched.
      def frame_sources(pane_id)
        evaluate_script(
          "Array.from(document.querySelectorAll('##{pane_id} iframe')).map(f => f.getAttribute('src'))"
        )
      end

      # Whether an <img> actually decoded. A thumbnail that fails is hidden by
      # receipt_viewer#imageFailed in favour of the document icon, so "visible"
      # alone would pass before the request even finished.
      def image_rendered?(selector, timeout: 5)
        deadline = Time.current + timeout
        script = <<~JS
          (() => { const i = document.querySelector("#{selector}");
                   return !!i && i.complete && i.naturalWidth > 0 })()
        JS
        loop do
          return true if evaluate_script(script)
          return false if Time.current > deadline

          sleep 0.1
        end
      end

      def resize_window_to(width, height)
        page.driver.browser.manage.window.resize_to(width, height)
      end

      # (a) The accessible reasons popover on the finance expenses table.
      test "needs-attention popover opens on click and closes on Escape" do
        expense = seed_expense(status: "Pending", receipt: false)

        visit admin_reimbursements_expense_edits_path

        panel = "reasons-edits-adv-#{expense.record_id}"
        trigger = find("button[aria-controls='#{panel}']")
        assert_equal "false", trigger["aria-expanded"], "popover starts collapsed"
        assert_no_selector "##{panel}" # panel hidden (Capybara ignores hidden by default)

        trigger.click
        assert_equal "true", trigger["aria-expanded"]
        assert_selector "##{panel}", visible: true
        within("##{panel}") { assert_text "no receipt" }

        # Escape closes it and returns focus to the trigger.
        trigger.send_keys(:escape)
        assert_equal "false", trigger["aria-expanded"]
        assert_no_selector "##{panel}"
      end

      # (a2) Clicking anywhere outside the popover closes it too, not just Escape.
      test "needs-attention popover closes on an outside click" do
        expense = seed_expense(status: "Pending", receipt: false)

        visit admin_reimbursements_expense_edits_path

        panel = "reasons-edits-adv-#{expense.record_id}"
        trigger = find("button[aria-controls='#{panel}']")
        trigger.click
        assert_equal "true", trigger["aria-expanded"]
        assert_selector "##{panel}", visible: true

        find("body").click(x: 5, y: 5) # anywhere outside the trigger/panel

        assert_equal "false", trigger["aria-expanded"]
        assert_no_selector "##{panel}"
      end

      # (b) The Fancybox lightbox still opens an image full screen — from inside
      # the viewer pane, which is where the lightbox link now lives.
      test "clicking a receipt thumbnail opens the Fancybox lightbox" do
        expense = seed_expense(status: "Approved", receipt: false)
        attach_test_receipt(expense, filename: "receipt.png", content_type: "image/png",
                            bytes: renderable_png_bytes)

        visit edit_admin_reimbursements_expense_edit_path(expense.record_id)

        assert_no_selector ".fancybox__container"
        find("button[aria-label='View receipt 1 of 1, receipt.png']").click
        find("a[data-fancybox='receipts-#{expense.record_id}']").click
        assert_selector ".fancybox__container", wait: 5

        # Escape dismisses the lightbox.
        find("body").send_keys(:escape)
        assert_no_selector ".fancybox__container"
      end

      # --- In-page receipt viewer -------------------------------------------

      # A card's receipt opens in place, one at a time, and only when asked for:
      # a twenty-claim queue that fetched twenty PDFs on load would be slower
      # than the tab-flipping it replaces, so the "no src before opening"
      # assertions are the point.
      test "a receipt pane opens on demand, lazily, and switches from the strip" do
        expense = seed_expense(status: "Pending", receipt: false)
        attach_test_receipt(expense, filename: "first.pdf", bytes: renderable_pdf_bytes)
        attach_test_receipt(expense, filename: "second.pdf", bytes: renderable_pdf_bytes)
        pane = "receipt-pane-#{expense.record_id}"

        visit admin_reimbursements_review_path

        # Closed, and nothing fetched.
        assert_no_selector "##{pane}"
        assert_equal [ nil, nil ], frame_sources(pane)

        find("button[aria-label='View receipt 1 of 2, first.pdf']").click

        assert_selector "##{pane}", visible: true
        first_src, second_src = frame_sources(pane)
        assert_match(/first\.pdf/, first_src.to_s, "opening loads the receipt asked for")
        assert_nil second_src, "the other receipt stays unfetched until it is asked for"

        find("button[aria-label='View receipt 2 of 2, second.pdf']").click

        assert_match(/second\.pdf/, frame_sources(pane).last.to_s)
        assert_equal "true", find("button[aria-label='View receipt 2 of 2, second.pdf']")["aria-expanded"]
        assert_equal "false", find("button[aria-label='View receipt 1 of 2, first.pdf']")["aria-expanded"]

        within("##{pane}") { click_button "Hide" }
        assert_no_selector "##{pane}"
      end

      # A PDF's first page renders fine, so it gets a real thumbnail rather than
      # the generic document icon an is-it-an-image test would leave it with.
      test "a PDF receipt renders a real first-page preview in the strip" do
        expense = seed_expense(status: "Pending", receipt: false)
        attach_test_receipt(expense, filename: "invoice.pdf", bytes: renderable_pdf_bytes)

        visit admin_reimbursements_review_path

        thumbnail = "button[aria-label='View receipt 1 of 1, invoice.pdf'] img"
        assert_selector thumbnail
        assert image_rendered?(thumbnail), "the PDF's first page must decode as a real preview"
        assert_no_selector "button[aria-label='View receipt 1 of 1, invoice.pdf'] i.fa-file-lines",
                           visible: true
      end

      # A malformed PDF only raises ActiveStorage::PreviewError when the preview
      # is REQUESTED, so a producer's dodgy upload surfaces as a failed thumbnail
      # request. It has to leave a document icon, not a broken image.
      test "a receipt whose preview cannot be generated falls back to the document icon" do
        expense = seed_expense(status: "Pending") # default bytes are a stub PDF header

        visit admin_reimbursements_review_path

        label = "button[aria-label='View receipt 1 of 1, receipt.pdf']"
        assert_selector "#{label} i.fa-file-lines", visible: true, wait: 5
        assert_no_selector "#{label} img", visible: true
      end

      # Side by side is the whole request; on a phone it has to stack instead of
      # squeezing both columns into unreadable slivers.
      test "the receipt pane sits beside the claim details, and stacks on a phone" do
        expense = seed_expense(status: "Pending", receipt: false)
        attach_test_receipt(expense, filename: "invoice.pdf", bytes: renderable_pdf_bytes)
        pane = "receipt-pane-#{expense.record_id}"

        visit admin_reimbursements_review_path
        find("button[aria-label='View receipt 1 of 1, invoice.pdf']").click
        assert_selector "##{pane}", visible: true

        details = find("form[action*='/save']").native.rect
        beside = find("##{pane}").native.rect
        assert_operator beside.x, :>, details.x + (details.width / 2),
                        "on a wide screen the receipt sits beside the details"
        assert_operator beside.y, :<, details.y + details.height,
                        "level with the details, not pushed below them"

        resize_window_to(390, 844)

        details = find("form[action*='/save']").native.rect
        stacked = find("##{pane}").native.rect
        assert_in_delta details.x, stacked.x, 24, "stacked, so both start at the same edge"
        assert_operator stacked.y, :>, details.y + details.height, "with the pane below the details"
      ensure
        resize_window_to(1400, 1400)
      end

      # The attach form, i.e. the last row of the receipts block. Reached through
      # its file field because the remove-receipt buttons post to a URL with the
      # same /receipts prefix.
      def attach_form
        find("input[name='receipts[]']").find(:xpath, "ancestor::form[1]")
      end

      # A claim with nothing to read beside the form must not be given a column
      # anyway. It used to get one regardless: two fifths of the card, stretched
      # to the height of the details, holding an attach button — and since a
      # receiptless claim always sorts into Needs attention, that empty block
      # landed at the bottom of the queue.
      test "a claim with no receipt is not given a receipt column at all" do
        seed_expense(status: "Pending", receipt: false)

        visit admin_reimbursements_review_path

        details = find("form[action*='/save']").native.rect
        receipts = attach_form.native.rect
        assert_in_delta details.x, receipts.x, 24,
                        "no side column, so the receipts block starts at the same edge as the details"
        assert_operator receipts.y, :>, details.y + details.height,
                        "and sits below the details rather than beside them"
      end

      # The column a receipted claim does get must end with its own content. A
      # stretched column rules the divider down blank space to the card floor,
      # which is what the empty area looked like.
      test "the receipt column ends with its content instead of stretching to the card floor" do
        expense = seed_expense(status: "Pending", receipt: false)
        attach_test_receipt(expense, filename: "invoice.pdf", bytes: renderable_pdf_bytes)

        visit admin_reimbursements_review_path
        assert_selector "button[aria-label='View receipt 1 of 1, invoice.pdf']"

        attach = attach_form.native.rect
        column = attach_form.find(:xpath, "..").native.rect
        assert_operator column.x, :>, find("form[action*='/save']").native.rect.x,
                        "the column is beside the details on a wide screen"
        assert_in_delta column.y + column.height, attach.y + attach.height, 8,
                        "the column stops at its last row rather than being stretched"
      end

      # (d) The Reconcile wizard's forms render their next step directly (the
      # stateless wizard re-POSTs the full paste, so it can't redirect). That
      # only works inside a Turbo Frame — outside one, Turbo Drive silently
      # discards a non-redirect form response and the button does nothing,
      # which is exactly the regression this guards against.
      test "reconcile Parse and match actually advances the wizard in a real browser" do
        visit admin_reimbursements_reconciliation_path

        # Error path: garbage renders the parse error in place.
        fill_in "Actuals data (tab- or comma-separated, include the header row)", with: "not parseable"
        click_on "Parse and match"
        assert_text "Could not parse actuals", wait: 5

        # Happy path: a valid row advances to the Step 2/3 preview.
        fill_in "Actuals data (tab- or comma-separated, include the header row)",
                with: "Nominal\tCost Centre\tRef\tDate\tPeriod\tNarrative\tNarrative 1\tDebit\tCredit\tNet\n" \
                      "439999\tF40\tBACS001\t15/03/2026\t03\tSystem Test Row\t\t123.45\t\t123.45"
        click_on "Parse and match"
        assert_text "Step 3: Apply reconciliation", wait: 5
        assert_text "Unmatched rows (1)"
      end

      # (d2) Two byte-identical offsetting pairs must be two independently
      # tickable rows in a real browser. On a content-only key both rows share
      # one DOM id, so the second row's label activates the FIRST checkbox and
      # unticking one silently offsets both, stamping a genuine transaction as
      # bookkeeping noise.
      test "unticking one of two identical offsetting pairs leaves the other ticked" do
        accrual = "331300\tF40\tJ000000884\t27/04/2026\t01\tVenue hire accrual\tShow\t10.00\t\t10.00"
        reversal = "331300\tF40\tJ000000884\t28/04/2026\t02\tVenue hire accrual\tShow\t\t10.00\t-10.00"
        header = "Nominal\tCost Centre\tRef\tDate\tPeriod\tNarrative\tNarrative 1\tDebit\tCredit\tNet"

        visit admin_reimbursements_reconciliation_path
        fill_in "Actuals data (tab- or comma-separated, include the header row)",
                with: [ header, accrual, reversal, accrual, reversal ].join("\n")
        click_on "Parse and match"

        assert_text "Offsetting pairs (2)", wait: 5
        boxes = all("input[type=checkbox][name='offset_pair_keys[]']")
        assert_equal 2, boxes.size
        assert_equal 2, boxes.map { |box| box[:id] }.uniq.size, "each pair needs its own DOM id"

        boxes.first.uncheck

        assert_not boxes.first.checked?
        assert boxes.last.checked?, "unticking one pair must not untick the other"
      end

      # (d3) The way back out of a mis-detected offsetting pair, clicked for
      # real: the confirm is a SweetAlert dialog (Turbo.config.forms.confirm is
      # replaced in setup/index.js), so a plain button_to + turbo_confirm has to
      # survive that indirection inside the results table.
      test "the Not offsetting button undoes a pair through its confirm dialog" do
        accrual = create_reimbursements_actual(nominal_code: "331300", period: "04",
                                               narrative: "Venue hire accrual",
                                               date: Date.new(2026, 6, 2), debit: BigDecimal("500.0"),
                                               reconciliation_status: "offset")
        reversal = create_reimbursements_actual(nominal_code: "331300", period: "05",
                                                narrative: "Venue hire accrual reversal",
                                                date: Date.new(2026, 6, 3), debit: nil,
                                                credit: BigDecimal("500.0"),
                                                reconciliation_status: "offset", offset_of: accrual)
        accrual.update!(offset_of: reversal)

        visit admin_reimbursements_actuals_path(include_offsets: "1")

        assert_selector "form[action*='unoffset']", count: 2
        first("form[action*='unoffset'] button").click
        within(".swal2-popup") { click_on "Yes" }

        assert_text "ordinary ledger rows again", wait: 5
        assert_no_selector "form[action*='unoffset']"
        assert_not accrual.reload.offset?
        assert_not reversal.reload.offset?
      end

      # (e) A rejected (422) form save must still SHOW its flash error. Turbo
      # never fires turbo:load for non-redirect form responses, so the old
      # turbo:load-only flash listener left these saves failing with zero
      # visible feedback — the page just redrew silently.
      test "a rejected settings save shows its validation error" do
        visit edit_admin_reimbursements_setting_path("fringe")
        fill_in "Receive mailbox (email-in)", with: "not-an-email"
        click_on "Save settings"

        assert_selector ".swal2-container", text: "Receive mailbox is invalid", wait: 5
      end

      # (f) The new-cost-centre form creates a row and lands on its settings
      # page. Plain fill + submit is safe here — this form has no markdown editor.
      test "creating a cost centre from the form lands on its settings page" do
        visit admin_reimbursements_settings_path
        click_on "New cost centre"

        fill_in "Name", with: "System Test Venue"
        fill_in "EUSA cost-centre code", with: "STV"
        fill_in "Receive mailbox (email-in)", with: "stv-in@example.co"
        fill_in "Send-from mailbox (drafts)", with: "stv-out@example.co"
        click_on "Create cost centre"

        # Auto-derived slug drives the settings URL we land on.
        assert_current_path edit_admin_reimbursements_setting_path("system-test-venue"), wait: 5
        assert_text "System Test Venue"

        created = ::Reimbursements::CostCentre.find_by(eusa_code: "STV")
        assert_equal "system-test-venue", created.key
        assert_equal "stv-in@example.co", created.receive_mailbox
      end

      # (g) Editing a Review card then hitting Approve must not silently drop the
      # edit: a dirty Save form pops the three-option confirmation dialog, and
      # Cancel leaves the page and the edit intact.
      test "a dirty review card intercepts Approve with the unsaved-edits dialog" do
        seed_expense(status: "Pending")

        visit admin_reimbursements_review_path

        assert_no_selector "dialog[open]", wait: 1
        fill_in "Description", with: "Edited in the browser"
        click_button "Approve", exact: true

        assert_selector "dialog[open]", wait: 5
        within("dialog[open]") do
          assert_button "Cancel"
          assert_button "Save Changes"
          assert_button "Discard Changes"
          assert_text(/save the changes before approving/i)
          click_button "Cancel"
        end

        # Cancel keeps us on the Review page with the edit still typed in.
        assert_no_selector "dialog[open]"
        assert_selector "h1", text: "Review Expenses"
        assert_field "Description", with: "Edited in the browser"
      end

      # (g3) The Save Changes branch, end to end. Nothing else drives
      # saveThenDecide / #injectEditFields: the server tests hand-craft the flat
      # params this JS is supposed to produce, so dropping the injected
      # save_changes input (or the edit fields themselves) would leave every
      # "Save Changes" click silently discarding the operator's edits and
      # deciding on the un-edited claim.
      test "Save Changes saves the edit and then runs the decision" do
        expense = seed_expense(status: "Pending", description: "Original wording")

        visit admin_reimbursements_review_path

        fill_in "Description", with: "Edited then saved"
        click_button "Approve", exact: true
        within("dialog[open]") { click_button "Save Changes" }

        assert_selector ".swal2-container", text: "Approved ##{expense.auto_number}", wait: 5
        expense.reload
        assert_equal "Edited then saved", expense.description, "the edit must be persisted"
        assert_equal ::Reimbursements::Status::APPROVED, expense.status, "and the decision must run"
      end

      # (g4) The Discard branch: the decision runs, the edit does NOT land.
      test "Discard Changes runs the decision without saving the edit" do
        expense = seed_expense(status: "Pending", description: "Original wording")

        visit admin_reimbursements_review_path

        fill_in "Description", with: "Edited then discarded"
        click_button "Approve", exact: true
        within("dialog[open]") { click_button "Discard Changes" }

        assert_selector ".swal2-container", text: "Approved ##{expense.auto_number}", wait: 5
        expense.reload
        assert_equal "Original wording", expense.description, "the discarded edit must not persist"
        assert_equal ::Reimbursements::Status::APPROVED, expense.status
      end

      # (g5) An aborted Save leaves its injected hidden inputs in the DOM unless
      # they are cleared, so the NEXT decision — including an explicit "Discard
      # Changes" — carries the edit and save_changes=1 and commits the very edit
      # the operator discarded. Reachable on the override-approve form, which
      # always carries a turbo-confirm the operator can cancel.
      test "an aborted Save Changes leaves nothing behind for a later Discard to commit" do
        owner = create_reimbursements_person(name: "Olga Owner", email: "olga@example.com")
        owned = create_reimbursements_budget(name: "Owned", nominal_code: "4100", owners: [ owner ])
        expense = create_reimbursements_expense(person: @person, budget: owned, status: "Pending",
                                                description: "Original wording")

        visit admin_reimbursements_review_path

        fill_in "Description", with: "Edited then abandoned"
        click_button "Approve (override sign-off)"
        within("dialog[open]") { click_button "Save Changes" }
        # The override form's own turbo-confirm: cancelling it aborts the submit
        # with the injected fields already appended to the form.
        within(".swal2-container") { click_button "Cancel" }
        assert_no_selector ".swal2-container"

        # Second run at the same decision, this time discarding the edit.
        click_button "Approve (override sign-off)"
        within("dialog[open]") { click_button "Discard Changes" }
        within(".swal2-container") { click_button "Yes" }

        assert_selector ".swal2-container", text: "Approved ##{expense.auto_number}", wait: 5
        expense.reload
        assert_equal "Original wording", expense.description,
                     "an abandoned Save must not be committed by a later Discard"
        assert_equal ::Reimbursements::Status::APPROVED, expense.status
      end

      # (g6) The native Escape key closes the dialog without going through the
      # Cancel button, so the close event is what has to reset the pending
      # decision. Behaviourally it must match Cancel: edit intact, nothing decided.
      test "Escape closes the unsaved-edits dialog and decides nothing" do
        expense = seed_expense(status: "Pending")

        visit admin_reimbursements_review_path

        fill_in "Description", with: "Edited in the browser"
        click_button "Approve", exact: true
        assert_selector "dialog[open]", wait: 5

        find("dialog[open]").send_keys(:escape)

        assert_no_selector "dialog[open]"
        assert_field "Description", with: "Edited in the browser"
        assert_equal ::Reimbursements::Status::PENDING, expense.reload.status
      end

      # (g7) The dirty check serialises the Save form as name=value pairs. Joined
      # RAW, a value containing the separators could make two DIFFERENT sets of
      # field values serialise to the same string — the form then reads as
      # pristine and the decision drops the edits without ever offering the
      # dialog. The pair below collides exactly that way unencoded: the seeded
      # payment reference is longer than the input's maxlength, which only
      # constrains typing, so both states are reachable in a real browser.
      test "the dirty check is not defeated by separators inside a field value" do
        expense = seed_expense(status: "Pending", description: "x",
                               payment_reference: "y&payment_reference=z")

        visit admin_reimbursements_review_path

        # Same unencoded serialisation as the seeded state, different values.
        fill_in "Description", with: "x&payment_reference=y"
        fill_in "Payment reference", with: "z"
        click_button "Approve", exact: true

        assert_selector "dialog[open]", wait: 5
        assert_equal ::Reimbursements::Status::PENDING, expense.reload.status,
                     "the decision must not have run behind the operator's back"
      end

      # (g2) A pristine card never shows the unsaved-edits dialog — the decision's
      # own turbo-confirm (a SweetAlert here) fires as usual.
      test "a pristine review card skips the dialog and runs the normal confirm" do
        seed_expense(status: "Pending")

        visit admin_reimbursements_review_path

        click_button "Reject", exact: true

        assert_no_selector "dialog[open]", wait: 1
        assert_selector ".swal2-container", wait: 5
      end

      # (c) The Review page subscribes to the live AI-verdict Turbo Stream.
      test "the Review page renders the AI-verdict Turbo Stream subscription" do
        # ai_check_status present so the page doesn't kick a background AI job.
        seed_expense(status: "Pending", receipt: false, ai_check_status: "pass")

        visit admin_reimbursements_review_path

        assert_selector "h1", text: "Review Expenses"
        # The <turbo-cable-stream-source> is an invisible custom element.
        assert_selector "turbo-cable-stream-source[signed-stream-name]", visible: :all
      end
    end
  end
end
