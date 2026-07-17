require "application_system_test_case"

module Admin
  module Reimbursements
    # Browser tests for the three finance-surface JS interactions that render
    # tests can't cover: the accessible needs-attention popover (open on click /
    # close on Escape), the Fancybox receipts lightbox, and the Review page's
    # live-AI-verdict Turbo Stream subscription.
    #
    # Data is Airtable-backed, so each test injects a fake Store through the
    # controllers' store_builder seam (the same seam the functional tests use) and
    # a fake modulus checker, so nothing hits Airtable or the gitignored Pay.UK
    # rule files. Capybara serves the app in-process, so setting the class
    # attributes here is visible to the request thread.
    class FinanceJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      EXP = FIELD_IDS[:expenses]

      # Always-VALID modulus verdict, so a fully-detailed payee never trips a
      # "needs attention" bank-details reason and "no receipt" is the only flag.
      class FakeChecker
        def check(_sort_code, _account_number)
          ::Reimbursements::ModulusCheck::VALID
        end
      end

      setup do
        grant_finance_permission(users(:member))
        @person = airtable_person_record(id: "recPer1", name: "Pat Producer", email: "pat@example.com",
                                         sort_code: "08-99-99", account_number: "66374958")
        @budget = airtable_budget_record(id: "recBud1", name: "Props", nominal_code: "4000")
        @checker = FakeChecker.new
        ExpenseEditsController.checker_builder = -> { @checker }
        ReviewController.checker_builder = -> { @checker }
        login_as users(:member)
      end

      teardown do
        BaseController.store_builder = -> { ::Reimbursements::Store.new }
        ExpenseEditsController.checker_builder = -> { ::Reimbursements::ModulusCheck.default_checker }
        ReviewController.checker_builder = -> { ::Reimbursements::ModulusCheck.default_checker }
      end

      def rebuild_store(expenses:)
        @store, @client = build_fake_store(expenses: expenses, people: [ @person ], budgets: [ @budget ])
        BaseController.store_builder = -> { @store }
      end

      # (a) The accessible reasons popover on the finance expenses table.
      test "needs-attention popover opens on click and closes on Escape" do
        rebuild_store(expenses: [ airtable_expense_record(id: "recExp1", status: "Pending", receipts: []) ])

        visit admin_reimbursements_expense_edits_path

        trigger = find("button[aria-controls='reasons-edits-adv-recExp1']")
        assert_equal "false", trigger["aria-expanded"], "popover starts collapsed"
        assert_no_selector "#reasons-edits-adv-recExp1" # panel hidden (Capybara ignores hidden by default)

        trigger.click
        assert_equal "true", trigger["aria-expanded"]
        assert_selector "#reasons-edits-adv-recExp1", visible: true
        within("#reasons-edits-adv-recExp1") { assert_text "no receipt" }

        # Escape closes it and returns focus to the trigger.
        trigger.send_keys(:escape)
        assert_equal "false", trigger["aria-expanded"]
        assert_no_selector "#reasons-edits-adv-recExp1"
      end

      # (a2) Clicking anywhere outside the popover closes it too, not just Escape.
      test "needs-attention popover closes on an outside click" do
        rebuild_store(expenses: [ airtable_expense_record(id: "recExp1", status: "Pending", receipts: []) ])

        visit admin_reimbursements_expense_edits_path

        trigger = find("button[aria-controls='reasons-edits-adv-recExp1']")
        trigger.click
        assert_equal "true", trigger["aria-expanded"]
        assert_selector "#reasons-edits-adv-recExp1", visible: true

        find("body").click(x: 5, y: 5) # anywhere outside the trigger/panel

        assert_equal "false", trigger["aria-expanded"]
        assert_no_selector "#reasons-edits-adv-recExp1"
      end

      # (b) The Fancybox lightbox opens on a receipt thumbnail.
      test "clicking a receipt thumbnail opens the Fancybox lightbox" do
        image = { "id" => "attImg", "filename" => "receipt.jpg", "url" => "https://airtable/img.jpg",
                  "size" => 100, "type" => "image/jpeg",
                  "thumbnails" => { "large" => { "url" => "https://airtable/thumb.jpg" } } }
        rebuild_store(expenses: [ airtable_expense_record(id: "recExp1", status: "Approved", receipts: [ image ]) ])

        visit edit_admin_reimbursements_expense_edit_path("recExp1")

        assert_no_selector ".fancybox__container"
        find("a[data-fancybox='receipts-recExp1']").click
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
        rebuild_store(expenses: [])

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

      # (e) A rejected (422) form save must still SHOW its flash error. Turbo
      # never fires turbo:load for non-redirect form responses, so the old
      # turbo:load-only flash listener left these saves failing with zero
      # visible feedback — the page just redrew silently.
      test "a rejected settings save shows its validation error" do
        rebuild_store(expenses: [])

        visit edit_admin_reimbursements_setting_path("fringe")
        fill_in "Receive mailbox (email-in)", with: "not-an-email"
        click_on "Save settings"

        assert_selector ".swal2-container", text: "Receive mailbox is invalid", wait: 5
      end

      # (c) The Review page subscribes to the live AI-verdict Turbo Stream.
      test "the Review page renders the AI-verdict Turbo Stream subscription" do
        # ai_check_status present so the page doesn't kick a background AI job.
        rebuild_store(expenses: [
          airtable_expense_record(id: "recExp1", status: "Pending",
                                  overrides: { EXP[:ai_check_status] => "pass" })
        ])

        visit admin_reimbursements_review_path

        assert_selector "h1", text: "Review Expenses"
        # The <turbo-cable-stream-source> is an invisible custom element.
        assert_selector "turbo-cable-stream-source[signed-stream-name]", visible: :all
      end
    end
  end
end
