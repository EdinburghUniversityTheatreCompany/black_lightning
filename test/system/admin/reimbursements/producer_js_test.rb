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
    end
  end
end
