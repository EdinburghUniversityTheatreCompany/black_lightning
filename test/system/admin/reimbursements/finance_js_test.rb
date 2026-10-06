require "application_system_test_case"

module Admin
  module Reimbursements
    # What only a browser sees on the finance screens. Capybara serves the app
    # in-process, so the class-attribute seams set here reach the request thread.
    class FinanceJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      # Always VALID, so "no receipt" is the only needs-attention flag.
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

      # Defaults to a PDF poppler can render: the suite's stub bytes raise
      # ActiveStorage::PreviewError when a browser requests a preview.
      def seed_expense(status:, receipt: true, **attrs)
        expense = create_reimbursements_expense(person: @person, budget: @budget, status: status,
                                                receipt: false, **attrs)
        attach_test_receipt(expense, bytes: renderable_pdf_bytes) if receipt
        expense
      end

      # Capybara re-raises app-server exceptions, so a test that uploads an unpreviewable
      # file must opt out. Deliberately not block-scoped: the preview is fetched
      # asynchronously and a late PreviewError lands after the body, during the session
      # reset in after_teardown, so the opt-out has to outlive it.
      def tolerate_server_errors
        Capybara.raise_server_errors = false
      end

      def after_teardown
        super # Capybara.reset_sessions! runs in here, and raises what it collected
      ensure
        Capybara.raise_server_errors = true
      end

      def renderable_pdf_bytes
        file_fixture("renderable_receipt.pdf").binread
      end

      def renderable_png_bytes
        file_fixture("renderable_receipt.png").binread
      end

      # The src attribute of every frame in a pane, in strip order; nil means never fetched.
      def frame_sources(pane_id)
        evaluate_script(
          "Array.from(document.querySelectorAll('##{pane_id} iframe')).map(f => f.getAttribute('src'))"
        )
      end

      # Whether an <img> decoded: a failed thumbnail is hidden by receipt_viewer#imageFailed,
      # so "visible" alone would pass before the request finished.
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

        trigger.send_keys(:escape)
        assert_equal "false", trigger["aria-expanded"]
        assert_no_selector "##{panel}"
      end

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

      # The Fancybox lightbox opens from inside the viewer pane.
      test "clicking a receipt thumbnail opens the Fancybox lightbox" do
        expense = seed_expense(status: "Approved", receipt: false)
        attach_test_receipt(expense, filename: "receipt.png", content_type: "image/png",
                            bytes: renderable_png_bytes)

        visit edit_admin_reimbursements_expense_edit_path(expense.record_id)

        assert_no_selector ".fancybox__container"
        find("button[aria-label='View receipt 1 of 1, receipt.png']").click
        find("a[data-fancybox='receipts-#{expense.record_id}']").click
        assert_selector ".fancybox__container", wait: 5

        find("body").send_keys(:escape)
        assert_no_selector ".fancybox__container"
      end

      # --- In-page receipt viewer -------------------------------------------

      # A receipt opens in place, one at a time, and only when asked for: a twenty-claim
      # queue fetching twenty PDFs on load would be slower than the tab-flipping it replaced.
      test "a receipt pane opens on demand, lazily, and switches from the strip" do
        expense = seed_expense(status: "Pending", receipt: false)
        attach_test_receipt(expense, filename: "first.pdf", bytes: renderable_pdf_bytes)
        attach_test_receipt(expense, filename: "second.pdf", bytes: renderable_pdf_bytes)
        pane = "receipt-pane-#{expense.record_id}"

        visit admin_reimbursements_review_path

        assert_no_selector "##{pane}"
        assert_equal [ nil, nil ], frame_sources(pane)

        # A receipt URL names the file by id, so it says which of the two was fetched.
        first, second = expense.reload.receipts

        find("button[aria-label='View receipt 1 of 2, first.pdf']").click

        assert_selector "##{pane}", visible: true
        first_src, second_src = frame_sources(pane)
        assert_equal first.url, first_src, "opening loads the receipt asked for"
        assert_nil second_src, "the other receipt stays unfetched until it is asked for"

        find("button[aria-label='View receipt 2 of 2, second.pdf']").click

        assert_equal second.url, frame_sources(pane).last
        assert_equal "true", find("button[aria-label='View receipt 2 of 2, second.pdf']")["aria-expanded"]
        assert_equal "false", find("button[aria-label='View receipt 1 of 2, first.pdf']")["aria-expanded"]

        within("##{pane}") { click_button "Hide" }
        assert_no_selector "##{pane}"
      end

      # A PDF gets a real first-page thumbnail, not the generic document icon.
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

      # A malformed PDF raises PreviewError only when the preview is requested, so it
      # surfaces as a failed thumbnail request. It must leave a document icon, not a broken image.
      test "a receipt whose preview cannot be generated falls back to the document icon" do
        expense = seed_expense(status: "Pending", receipt: false)
        attach_test_receipt(expense) # the suite default: a stub PDF header poppler cannot render
        tolerate_server_errors

        visit admin_reimbursements_review_path

        label = "button[aria-label='View receipt 1 of 1, receipt.pdf']"
        assert_selector "#{label} i.fa-file-lines", visible: true, wait: 5
        assert_no_selector "#{label} img", visible: true
      end

      # On a phone the columns must stack, not squeeze into slivers.
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

      # The last row of the receipts block, found through its file field because the
      # remove-receipt buttons post to a URL with the same /receipts prefix.
      def attach_form
        find("input[name='receipts[]']").find(:xpath, "ancestor::form[1]")
      end

      # A claim with no receipt gets no column: two fifths of the card holding only an
      # attach button.
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

      # The receipt column must end with its content, not rule the divider down blank
      # space to the card floor.
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

      # The wizard renders its next step directly (the stateless re-POST can't redirect),
      # which works only inside a Turbo Frame: outside one Turbo drops the response and the
      # button does nothing.
      test "reconcile Parse and match actually advances the wizard in a real browser" do
        visit admin_reimbursements_reconciliation_path

        fill_in "Actuals data (tab- or comma-separated, include the header row)", with: "not parseable"
        click_on "Parse and match"
        assert_text "Could not parse actuals", wait: 5

        fill_in "Actuals data (tab- or comma-separated, include the header row)",
                with: "Nominal\tCost Centre\tRef\tDate\tPeriod\tNarrative\tNarrative 1\tDebit\tCredit\tNet\n" \
                      "439999\tF40\tBACS001\t15/03/2026\t03\tSystem Test Row\t\t123.45\t\t123.45"
        click_on "Parse and match"
        assert_text "Step 3: Apply reconciliation", wait: 5
        assert_text "Unmatched rows (1)"
        assert_text "Nobody is emailed"
      end

      # Identical offsetting pairs need distinct DOM ids, or the second row's label
      # activates the first checkbox and unticking one unticks both.
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

      # The confirm is a SweetAlert dialog (Turbo.config.forms.confirm is replaced in
      # setup/index.js), which a plain button_to + turbo_confirm has to survive.
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

      # A rejected (422) save must still show its flash error: Turbo fires no turbo:load
      # for a non-redirect response.
      test "a rejected settings save shows its validation error" do
        visit edit_admin_reimbursements_setting_path("fringe")
        fill_in "Receive mailbox (email-in)", with: "not-an-email"
        click_on "Save settings"

        assert_selector ".swal2-container", text: "Receive mailbox is invalid", wait: 5
      end

      # Capybara's `select` cannot drive a Tom Select (select_controller.js hides the
      # <select>): click the widget instead.
      def tom_select(option_text, select_id:)
        wrapper = find("##{select_id}", visible: :any).find(:xpath, "..")
        wrapper.find(".ts-control").click
        wrapper.find(".ts-dropdown-content .option", text: option_text, match: :first).click
      end

      # A remote Tom Select loads nothing until typed into, and its search box is inside the
      # dropdown: open it, type, then click the option the AJAX round trip returned.
      def tom_select_remote(query, option_text, select_id:)
        wrapper = find("##{select_id}", visible: :any).find(:xpath, "..")
        wrapper.find(".ts-control").click
        wrapper.find(".ts-dropdown input").set(query)
        wrapper.find(".ts-dropdown-content .option", text: option_text, match: :first, wait: 5).click
      end

      # Plain fill + submit is safe here: no markdown editor.
      test "creating a cost centre from the form lands on its settings page" do
        visit admin_reimbursements_settings_path
        click_on "New cost centre"

        fill_in "Name", with: "System Test Venue"
        fill_in "EUSA cost-centre code", with: "STV"
        fill_in "Receive mailbox (email-in)", with: "stv-in@example.co"
        fill_in "Send-from mailbox (drafts)", with: "stv-out@example.co"
        fill_in "Notification email", with: "stv-finance@example.co"
        click_on "Create cost centre"

        assert_current_path edit_admin_reimbursements_setting_path("system-test-venue"), wait: 5
        assert_text "System Test Venue"

        created = ::Reimbursements::CostCentre.find_by(eusa_code: "STV")
        assert_equal "system-test-venue", created.key
        assert_equal "stv-in@example.co", created.receive_mailbox
        assert_equal [ "stv-finance@example.co" ], created.notification_emails
      end

      # A dirty card must not silently drop its edit on Approve: it pops the three-option
      # dialog, and Cancel leaves the edit intact.
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

        assert_no_selector "dialog[open]"
        assert_selector "h1", text: "Review Expenses"
        assert_field "Description", with: "Edited in the browser"
      end

      # Save Changes is the only end-to-end driver of saveThenDecide / #injectEditFields:
      # the server tests hand-craft the params, so dropping the injected inputs would
      # silently discard every edit.
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

      # Discard: the decision runs, the edit does not land.
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

      # An aborted Save must not leave injected inputs in the DOM for a later Discard to
      # commit. Reachable on the override-approve form, whose turbo-confirm can be cancelled.
      test "an aborted Save Changes leaves nothing behind for a later Discard to commit" do
        owner = create_reimbursements_person(name: "Olga Owner", email: "olga@example.com")
        owned = create_reimbursements_budget(name: "Owned", nominal_code: "4100", owners: [ owner ])
        expense = seed_expense(status: "Pending", budget: owned, description: "Original wording")

        # Olga's gate is unmet, so the claim is on Awaiting owner, where the override form lives.
        visit admin_reimbursements_review_path(tab: "awaiting_owner")

        fill_in "Description", with: "Edited then abandoned"
        click_button "Approve (override sign-off)"
        within("dialog[open]") { click_button "Save Changes" }
        # Cancelling the override's own confirm aborts the submit with the fields appended.
        within(".swal2-container") { click_button "Cancel" }
        assert_no_selector ".swal2-container"

        click_button "Approve (override sign-off)"
        within("dialog[open]") { click_button "Discard Changes" }
        within(".swal2-container") { click_button "Yes" }

        assert_selector ".swal2-container", text: "Approved ##{expense.auto_number}", wait: 5
        expense.reload
        assert_equal "Original wording", expense.description,
                     "an abandoned Save must not be committed by a later Discard"
        assert_equal ::Reimbursements::Status::APPROVED, expense.status
      end

      # Escape bypasses the Cancel button, so the close event must reset the pending
      # decision, matching Cancel.
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

      # The dirty check must encode separators, or two different sets of values serialise
      # alike, the form reads as pristine and the decision drops the edits. The seeded
      # payment reference exceeds maxlength, which only constrains typing.
      test "the dirty check is not defeated by separators inside a field value" do
        expense = seed_expense(status: "Pending", description: "x",
                               payment_reference: "y&payment_reference=z")

        visit admin_reimbursements_review_path

        fill_in "Description", with: "x&payment_reference=y"
        fill_in "Payment reference", with: "z"
        click_button "Approve", exact: true

        assert_selector "dialog[open]", wait: 5
        assert_equal ::Reimbursements::Status::PENDING, expense.reload.status,
                     "the decision must not have run behind the operator's back"
      end

      # A pristine card skips the dialog; the decision's own confirm fires. The reason is
      # filled in first because the box is `required`.
      test "a pristine review card skips the dialog and runs the normal confirm" do
        seed_expense(status: "Pending")

        visit admin_reimbursements_review_path

        fill_in "Reason for rejection", with: "No receipt"
        click_button "Reject", exact: true

        assert_no_selector "dialog[open]", wait: 1
        assert_selector ".swal2-container", wait: 5
      end

      # A fragment in a redirect does not survive a Turbo form submission (fetch follows the
      # 302 and never transmits it), so ?focus= is what scrolls to the next card.
      test "approving a card comes back scrolled to the next one" do
        first = seed_expense(status: "Pending", amount: 111, amount_excl_vat: 100)
        second = seed_expense(status: "Pending", amount: 222, amount_excl_vat: 200)

        visit admin_reimbursements_review_path
        within("#expense-#{first.record_id}") { click_button "Approve", exact: true }

        assert_current_path(/focus=expense-#{second.record_id}/, url: false, wait: 5)
        # The admin layout scrolls inside <main>, not on the document.
        scrolled = page.evaluate_script("document.querySelector('main').scrollTop")
        assert scrolled.to_i.positive?,
               "expected <main> to have scrolled to the anchored card, got scrollTop #{scrolled}"
      end

      # Only a browser sees `required` stop a blank rejection before the can't-be-undone
      # confirm; a request test POSTs straight to the action.
      test "a blank rejection reason never reaches the can't-be-undone confirm" do
        seed_expense(status: "Pending")

        visit admin_reimbursements_review_path

        click_button "Reject", exact: true

        assert_no_selector ".swal2-container", wait: 2
        assert_no_selector "dialog[open]", wait: 1
      end

      # The bulk reason box is shared with "Approve selected", so it cannot be `required`:
      # Reject selected is disabled until a reason is typed.
      test "bulk Reject selected stays disabled until a reason is typed" do
        expense = seed_expense(status: "Pending")

        visit admin_reimbursements_review_path
        check "select_#{expense.record_id}"

        assert_button "Reject selected", disabled: true
        assert_button "Approve selected", disabled: false,
                      exact: true
        fill_in "Reason (required to reject)", with: "Duplicate"

        assert_button "Reject selected", disabled: false
      end

      # --- Bank-detail masking ------------------------------------------------

      # Build Batch would otherwise show every payee's account number on load.
      test "bank details on Build Batch are masked until revealed" do
        ::Reimbursements::CostCentre.default.update!(
          sharepoint_receipts_drive_id: "drvR", sharepoint_receipts_folder_id: "fldR",
          sharepoint_bacs_drive_id: "drvB", sharepoint_bacs_folder_id: "fldB"
        )
        seed_expense(status: "Approved")

        visit new_admin_reimbursements_batch_path

        value = "[data-bank-details-target='value']"
        assert_selector value, text: "****9999 / ****4958"
        assert_no_text "66374958"

        click_button "Reveal"

        assert_selector value, text: "08-99-99 / 66374958"
        assert_selector "button[aria-pressed='true']", text: "Hide"

        click_button "Hide"

        assert_selector value, text: "****9999 / ****4958"
        assert_no_text "66374958"
      end

      # The People fields hold the real values to be editable, so they hide like a password.
      test "the People registry hides bank details in the edit fields until revealed" do
        visit admin_reimbursements_people_path
        find("summary", text: "Pat Producer").click

        field = find_field("Account number", type: :password, visible: :all)
        assert_equal "66374958", field.value, "the field must hold the real value to be editable"

        click_button "Reveal"

        assert_selector "input#account_number_#{@person.record_id}[type='text']"
        assert_equal "66374958", find_field("Account number").value
      end

      # --- Registering a user as a payee --------------------------------------
      #
      # A request test cannot see form structure (form_with inside CardComponent puts the
      # footer submit outside the <form>) nor drive the Tom Select user picker.
      test "finance registers an existing user account as a payee, with no bank details" do
        visit admin_reimbursements_people_path
        click_on "Register a person"

        tom_select_remote "Cyclops", "Cyclops Cat", select_id: "user_id"
        click_on "Add to the registry"

        assert_current_path admin_reimbursements_people_path, wait: 5
        assert_text "Cyclops Cat"

        registered = ::Reimbursements::Person.find_by(email: users(:user).email)
        assert_not_nil registered, "the submit button must actually submit the form"
        assert_nil registered.payment_details, "no bank details are collected here"
        assert_equal registered.id, users(:user).reload.reimbursements_person_id
      end

      # --- Linking an EUSA row to a claim -------------------------------------
      #
      # Same form-structure trap as above: functional tests POST straight to the action.
      test "linking an EUSA row settles the claim and corrects an international amount" do
        claim = create_reimbursements_expense(
          person: @person, budget: @budget, status: ::Reimbursements::Status::SUBMITTED,
          amount: BigDecimal("230.00"), amount_excl_vat: BigDecimal("230.00"),
          description: "Festival insurance", receipt: false,
          payment_method: ::Reimbursements::Expense::PAYMENT_METHOD_INTERNATIONAL,
          foreign_amount: BigDecimal("266.69"),
          foreign_currency: ::Reimbursements::Expense::CURRENCY_EUR
        )
        actual = create_reimbursements_actual(
          nominal_code: "4000", narrative: "AUSLAND GMBH", debit: BigDecimal("236.10"),
          date: Date.new(2026, 6, 1)
        )

        visit link_expense_admin_reimbursements_actual_path(actual.record_id)
        choose "expense_id_#{claim.record_id}"
        click_on "Link and mark Paid"

        assert_current_path admin_reimbursements_actuals_path
        settled = claim.reload
        assert_equal ::Reimbursements::Status::PAID, settled.status
        assert_equal BigDecimal("236.10"), settled.amount,
                     "the estimate must be corrected to what EUSA charged"
        assert_equal claim.id, ::Reimbursements::EusaActual.find(actual.id)[:expense_id]
      end
    end
  end
end
