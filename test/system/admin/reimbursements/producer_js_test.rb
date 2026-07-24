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
        # No Gemini in the browser test; extract just fails softly.
        ExpensesController.extractor_builder = -> { failing_extractor }
        login_as users(:member)
      end

      teardown do
        ExpensesController.extractor_builder = -> { ::Reimbursements::Extractor.new }
      end

      def failing_extractor
        Object.new.tap do |ext|
          def ext.extract(**) = ::Reimbursements::Extractor::Extraction.new(error: "no gemini in test")
        end
      end

      # A stub that returns a canned extraction (recording the mode it was asked
      # for) so the browser can exercise the consent radios and the prefill,
      # without any real Gemini call.
      def prefilling_extractor(extraction)
        Object.new.tap do |ext|
          ext.define_singleton_method(:extract) { |**| extraction }
        end
      end

      def canned_extraction(**overrides)
        ::Reimbursements::Extractor::Extraction.new(
          merchant: "Acme", total_amount: BigDecimal("42.00"), vat_amount: BigDecimal("7.00"),
          vat_itemised: true, suggested_description: "Set timber",
          suggested_payment_reference: "INV-1001", **overrides
        )
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

      # The scan is opt-in: the consent choice is hidden until a receipt is
      # attached, and nothing is sent to Gemini until the submitter picks one.
      test "the consent choice appears only after a receipt is attached" do
        visit new_admin_reimbursements_expense_path

        # Present in the DOM but hidden until a receipt is picked.
        assert_selector "[data-reimbursements-receipt-target='consent']", visible: :hidden
        assert_no_text "Read the receipt to prefill the form?"

        attach_file "reimbursements_expense_form_receipts",
                    Rails.root.join("test/fixtures/files/reimbursements_receipt.pdf")

        assert_text "Read the receipt to prefill the form?"
        assert_text "We use Gemini's free tier"
      end

      test "choosing 'to be reimbursed to myself' prefills the everyday fields, not bank details" do
        ExpensesController.extractor_builder = -> { prefilling_extractor(canned_extraction) }
        visit new_admin_reimbursements_expense_path

        attach_file "reimbursements_expense_form_receipts",
                    Rails.root.join("test/fixtures/files/reimbursements_receipt.pdf")
        choose "Yes, to be reimbursed to myself"

        assert_text "Prefilled from your receipt", wait: 5
        assert_equal "42.0", page.find_field("Amount (£, incl. VAT)").value
        # Self mode never returns bank details, so the payee trio stays empty.
        assert_empty page.find_field("Payee account name").value
      end

      test "choosing the invoice option prefills the third-party payee bank details" do
        extraction = canned_extraction(payee_name: "Acme Props Ltd",
                                       sort_code: "12-34-56", account_number: "12345678")
        ExpensesController.extractor_builder = -> { prefilling_extractor(extraction) }
        visit new_admin_reimbursements_expense_path

        attach_file "reimbursements_expense_form_receipts",
                    Rails.root.join("test/fixtures/files/reimbursements_receipt.pdf")
        choose "Yes, as an invoice paid out to the bank details listed on the invoice"

        assert_text "Prefilled from your receipt", wait: 5
        assert_equal "Acme Props Ltd", page.find_field("Payee account name").value
        assert_equal "12-34-56", page.find_field("Payee sort code").value
        assert_equal "12345678", page.find_field("Payee account number").value
      end

      test "choosing 'I will fill in the details myself' sends nothing to Gemini" do
        # If this option ever hit the endpoint, the raising extractor would 500
        # the request; the status line must instead confirm nothing was sent.
        ExpensesController.extractor_builder = -> { raise "must not scan when the submitter declined" }
        visit new_admin_reimbursements_expense_path

        attach_file "reimbursements_expense_form_receipts",
                    Rails.root.join("test/fixtures/files/reimbursements_receipt.pdf")
        choose "No, I will fill in all the details myself"

        assert_text "nothing was sent to Google"
        assert_empty page.find_field("Amount (£, incl. VAT)").value
      end
    end
  end
end
