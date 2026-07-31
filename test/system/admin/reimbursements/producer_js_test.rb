require "application_system_test_case"

module Admin
  module Reimbursements
    # Browser tests for the producer-facing expense form's JS that render/
    # functional tests can't cover. Data is served by the DatabaseStore from
    # real seeded rows.
    class ProducerJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      setup do
        grant_producer_permission(users(:member))
        create_reimbursements_person(email: users(:member).email)
        create_reimbursements_budget(name: "Props")
        login_as users(:member)
      end

      # The form's selects are Tom Select widgets (select_controller.js), which
      # hide the original <select> — Capybara's own #select can't touch it. Drive
      # the widget the way a producer does: open its control, click the option.
      # Tom Select fires a native change on the underlying select, so Stimulus
      # actions bound to it still run.
      def tom_select(option_text, select_id:)
        wrapper = find("##{select_id}", visible: :any).find(:xpath, "..")
        wrapper.find(".ts-control").click
        wrapper.find(".ts-dropdown-content .option", text: option_text, match: :first).click
      end

      # The whole point of the DataTransfer restore: a receipt the producer
      # attached survives a server validation 422, instead of silently
      # vanishing from the un-repopulatable file input.
      test "an attached receipt survives a failed submit" do
        visit new_admin_reimbursements_expense_path

        attach_file "reimbursements_expense_form_receipts",
                    Rails.root.join("test/fixtures/files/reimbursements_receipt.pdf")
        fill_in "Amount (£, incl. VAT)", with: "10.00"
        fill_in "Amount excl. VAT (£)", with: "8.00"
        # Fill the other HTML5-required fields so Submit reaches the server;
        # leave only Budget blank (it's star-only client-side but required
        # server-side), so the submit fails server-side and the form re-renders
        # -- the case where the attached file would otherwise be lost.
        fill_in "Description", with: "Fake blood for the show"
        fill_in "Payment reference", with: "PROPS TEST"
        click_on "Submit expense"

        assert_text "Kept the receipt you attached", wait: 5
        # The file is still selected on the re-rendered input.
        still_attached = page.evaluate_script(
          "document.getElementById('reimbursements_expense_form_receipts').files.length"
        )
        assert_equal 1, still_attached, "the receipt must survive the failed submit"
      end

      # An Invoice pays the supplier, so the payee trio stops being optional.
      # The label has to track the type select live — a producer who reads
      # "(optional)", leaves the trio blank and hits Submit gets a hard stop.
      test "picking Invoice marks the payee details required" do
        visit new_admin_reimbursements_expense_path

        assert_selector "[data-reimbursements-receipt-target='payeeOptional']", text: "(optional)"
        assert_selector "[data-reimbursements-receipt-target='payeeRequired']", visible: :hidden

        tom_select "Invoice", select_id: "reimbursements_expense_form_expense_type"

        assert_selector "[data-reimbursements-receipt-target='payeeRequired']",
                        text: "(required for an invoice)"
        assert_selector "[data-reimbursements-receipt-target='payeeOptional']", visible: :hidden

        tom_select "Reimbursement", select_id: "reimbursements_expense_form_expense_type"

        assert_selector "[data-reimbursements-receipt-target='payeeOptional']", text: "(optional)"
      end

      # The server-side hard block, and — just as important — that its reason is
      # actually READABLE: it lands on :base, which the generic error banner
      # doesn't list, so an unrendered base error would fail the form with no
      # visible cause at all.
      test "submitting an invoice with no payee details shows why it was blocked" do
        visit new_admin_reimbursements_expense_path

        attach_file "reimbursements_expense_form_receipts",
                    Rails.root.join("test/fixtures/files/reimbursements_receipt.pdf")
        tom_select "Invoice", select_id: "reimbursements_expense_form_expense_type"
        fill_in "Amount (£, incl. VAT)", with: "42.00"
        fill_in "Amount excl. VAT (£)", with: "35.00"
        tom_select "Props", select_id: "reimbursements_expense_form_budget_record_id"
        fill_in "Description", with: "Set timber from Acme"
        fill_in "Payment reference", with: "INV-1001"
        click_on "Submit expense"

        assert_text "An Invoice is paid straight to the supplier", wait: 5
        assert_text "change the type to Reimbursement instead"
        assert_equal 0, ::Reimbursements::Expense.count, "nothing may be written"
      end

      # With extraction gone these are the last untested behaviours the Stimulus
      # controller still owns, and #parseAmount's comma rule is exactly the kind
      # of thing that regresses silently: "999,99" is a decimal comma, not a
      # thousands separator, so a naive strip read it as 99999 and demanded a
      # confirmation the server would never have asked for.
      test "the large-amount confirmation appears as the amount crosses the threshold" do
        visit new_admin_reimbursements_expense_path

        assert_selector "[data-reimbursements-receipt-target='largeAmountWarning']", visible: :hidden

        fill_in "Amount (£, incl. VAT)", with: "1000"
        assert_selector "[data-reimbursements-receipt-target='largeAmountWarning']", visible: :visible

        fill_in "Amount (£, incl. VAT)", with: "999,99"
        assert_selector "[data-reimbursements-receipt-target='largeAmountWarning']", visible: :hidden,
                        wait: 2
      end

      test "the payment-reference counter tracks what EUSA will actually keep" do
        visit new_admin_reimbursements_expense_path
        limit = ::Reimbursements::ExpenseForm::REFERENCE_LIMIT

        assert_selector "[data-reimbursements-receipt-target='referenceCounter']",
                        text: "#{limit} of #{limit} characters left"

        fill_in "Payment reference", with: "PROPS"
        assert_selector "[data-reimbursements-receipt-target='referenceCounter']",
                        text: "#{limit - 5} of #{limit} characters left"
      end
    end
  end
end
