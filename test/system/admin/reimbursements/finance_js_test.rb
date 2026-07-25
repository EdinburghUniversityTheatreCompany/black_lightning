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

      # (b) The Fancybox lightbox opens on a receipt thumbnail.
      test "clicking a receipt thumbnail opens the Fancybox lightbox" do
        expense = seed_expense(status: "Approved", receipt: false)
        attach_test_receipt(expense, filename: "receipt.jpg", content_type: "image/jpeg",
                            bytes: "JPEGDATA")

        visit edit_admin_reimbursements_expense_edit_path(expense.record_id)

        assert_no_selector ".fancybox__container"
        find("a[data-fancybox='receipts-#{expense.record_id}']").click
        assert_selector ".fancybox__container", wait: 5

        # Escape dismisses the lightbox.
        find("body").send_keys(:escape)
        assert_no_selector ".fancybox__container"
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
      # tickable rows in a real browser. On a content-only key both rows shared
      # one DOM id, so the second row's label activated the FIRST checkbox and
      # unticking one silently offset both, stamping a genuine transaction as
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
