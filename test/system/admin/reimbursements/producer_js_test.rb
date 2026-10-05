require "application_system_test_case"

module Admin
  module Reimbursements
    # The producer expense form's JavaScript.
    class ProducerJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      setup do
        grant_producer_permission(users(:member))
        create_reimbursements_person(email: users(:member).email)
        create_reimbursements_budget(name: "Props")
        login_as users(:member)
      end

      # Tom Select hides the <select>, so Capybara's #select can't reach it.
      def tom_select(option_text, select_id:)
        wrapper = find("##{select_id}", visible: :any).find(:xpath, "..")
        wrapper.find(".ts-control").click
        wrapper.find(".ts-dropdown-content .option", text: option_text, match: :first).click
      end

      # A file input cannot be repopulated by the server, so the controller
      # restores it through a DataTransfer.
      test "an attached receipt survives a failed submit" do
        visit new_admin_reimbursements_expense_path

        attach_file "reimbursements_expense_form_receipts",
                    Rails.root.join("test/fixtures/files/reimbursements_receipt.pdf")
        fill_in "Amount (£, incl. VAT)", with: "10.00"
        fill_in "Amount excl. VAT (£)", with: "8.00"
        # Budget left blank, so the submit reaches the server and fails there.
        fill_in "Description", with: "Fake blood for the show"
        fill_in "Payment reference", with: "PROPS TEST"
        click_on "Submit expense"

        assert_text "Kept the receipt you attached", wait: 5
        still_attached = page.evaluate_script(
          "document.getElementById('reimbursements_expense_form_receipts').files.length"
        )
        assert_equal 1, still_attached, "the receipt must survive the failed submit"
      end

      # Honeybadger 134234926. Only a browser test posts exactly what the picker
      # rendered and sees the input survive the re-render.
      test "a budget deleted while the form is open fails the submit, not the claim" do
        doomed = create_reimbursements_budget(name: "Costumes", nominal_code: "4100")
        visit new_admin_reimbursements_expense_path

        attach_file "reimbursements_expense_form_receipts",
                    Rails.root.join("test/fixtures/files/reimbursements_receipt.pdf")
        fill_in "Amount (£, incl. VAT)", with: "42.00"
        fill_in "Amount excl. VAT (£)", with: "35.00"
        tom_select "Costumes", select_id: "reimbursements_expense_form_budget_record_id"
        fill_in "Description", with: "Ruff, doublet and hose"
        fill_in "Payment reference", with: "COSTUMES ACT1"

        doomed.destroy!

        click_on "Submit expense"

        assert_text "no longer available", wait: 5
        assert_equal 0, ::Reimbursements::Expense.count, "nothing may be written"
        assert_equal "Ruff, doublet and hose",
                     find("#reimbursements_expense_form_description").value
        assert_equal "COSTUMES ACT1",
                     find("#reimbursements_expense_form_payment_reference").value
        assert_equal "42.00", find("#reimbursements_expense_form_amount").value
        assert_equal "35.00", find("#reimbursements_expense_form_amount_excl_vat").value
      end

      # A deactivated budget still satisfies the foreign key, so this one never
      # 500ed — it silently accepted a claim against a line finance had retired.
      test "a budget deactivated while the form is open is refused the same way" do
        retired = create_reimbursements_budget(name: "Costumes", nominal_code: "4100")
        visit new_admin_reimbursements_expense_path

        attach_file "reimbursements_expense_form_receipts",
                    Rails.root.join("test/fixtures/files/reimbursements_receipt.pdf")
        fill_in "Amount (£, incl. VAT)", with: "42.00"
        fill_in "Amount excl. VAT (£)", with: "35.00"
        tom_select "Costumes", select_id: "reimbursements_expense_form_budget_record_id"
        fill_in "Description", with: "Ruff, doublet and hose"
        fill_in "Payment reference", with: "COSTUMES ACT1"

        retired.update!(active: false)

        click_on "Submit expense"

        assert_text "no longer available", wait: 5
        assert_equal 0, ::Reimbursements::Expense.count, "nothing may be written"
        assert_equal "Ruff, doublet and hose",
                     find("#reimbursements_expense_form_description").value
      end

      # --- The international rail --------------------------------------------

      # A hidden input carrying `required` silently blocks the whole submit, and
      # simple_form emits it from `required:` whatever input_html says, so the
      # attribute has to follow the active rail.
      test "switching payment method moves the required attribute with the fields" do
        visit new_admin_reimbursements_expense_path
        required = lambda { |field|
          page.evaluate_script(
            "document.querySelector('[name=\"reimbursements_expense_form[#{field}]\"]').required"
          )
        }

        assert required.call("amount"), "the UK amount is required on the UK rail"
        assert_not required.call("foreign_amount"), "a hidden required input blocks the whole form"

        tom_select "International (IBAN)", select_id: "reimbursements_expense_form_payment_method"

        assert required.call("foreign_amount")
        assert_not required.call("amount"), "the UK amount is hidden now, so it must not be required"
        assert_not required.call("amount_excl_vat")
      end

      # Nobody has an IBAN on file, so the payee trio is always required here.
      test "switching to international relabels the payee section as required" do
        visit new_admin_reimbursements_expense_path
        assert_text "Pay someone else (optional)"

        tom_select "International (IBAN)", select_id: "reimbursements_expense_form_payment_method"

        assert_text "Pay someone else (required)"
        assert_text "there is nothing on file to fall back to"
        assert_selector "label", text: "Payee IBAN"
        assert_no_selector "label", text: "Payee sort code", visible: true
      end

      test "an international claim submits on the invoice amount alone, in euros by default" do
        visit new_admin_reimbursements_expense_path

        attach_file "reimbursements_expense_form_receipts",
                    Rails.root.join("test/fixtures/files/reimbursements_receipt.pdf")
        tom_select "International (IBAN)", select_id: "reimbursements_expense_form_payment_method"
        fill_in "Amount, as printed on the invoice", with: "266.69"
        tom_select "Props", select_id: "reimbursements_expense_form_budget_record_id"
        fill_in "Description", with: "Festival insurance"
        fill_in "Payment reference", with: "INS-2026"
        fill_in "Payee account name", with: "Ausland GmbH"
        fill_in "Payee IBAN", with: "DE89 3704 0044 0532 0130 00"
        fill_in "Payee BIC / SWIFT code", with: "DEUTDEFF500"
        click_on "Submit expense"

        assert_text "Expense submitted", wait: 5
        expense = ::Reimbursements::Expense.order(:id).last
        assert expense.international?
        assert_equal BigDecimal("266.69"), expense.foreign_amount
        assert_equal ::Reimbursements::Expense::CURRENCY_EUR, expense.foreign_currency,
                     "the picker opens on euros, the common case"
        assert_nil expense.amount, "finance supplies the GBP figure at review"
      end

      test "a producer can pick a currency other than euros" do
        visit new_admin_reimbursements_expense_path

        attach_file "reimbursements_expense_form_receipts",
                    Rails.root.join("test/fixtures/files/reimbursements_receipt.pdf")
        tom_select "International (IBAN)", select_id: "reimbursements_expense_form_payment_method"
        tom_select "USD", select_id: "reimbursements_expense_form_foreign_currency"
        fill_in "Amount, as printed on the invoice", with: "500.00"
        tom_select "Props", select_id: "reimbursements_expense_form_budget_record_id"
        fill_in "Description", with: "US touring insurance"
        fill_in "Payment reference", with: "INS-USD"
        fill_in "Payee account name", with: "Stateside Insurance Inc"
        fill_in "Payee IBAN", with: "DE89 3704 0044 0532 0130 00"
        fill_in "Payee BIC / SWIFT code", with: "DEUTDEFF500"
        click_on "Submit expense"

        assert_text "Expense submitted", wait: 5
        expense = ::Reimbursements::Expense.order(:id).last
        assert_equal "USD", expense.foreign_currency
        assert_equal BigDecimal("500.00"), expense.foreign_amount
      end

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

      # The reason lands on :base, which the generic error banner does not list.
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

      # "999,99" is a decimal comma; a naive strip reads it as 99999.
      test "the large-amount confirmation appears as the amount crosses the threshold" do
        visit new_admin_reimbursements_expense_path

        assert_selector "[data-reimbursements-receipt-target='largeAmountWarning']", visible: :hidden

        fill_in "Amount (£, incl. VAT)", with: "1000"
        assert_selector "[data-reimbursements-receipt-target='largeAmountWarning']", visible: :visible

        fill_in "Amount (£, incl. VAT)", with: "999,99"
        assert_selector "[data-reimbursements-receipt-target='largeAmountWarning']", visible: :hidden,
                        wait: 2
      end

      test "the missing-VAT confirmation appears as the two amounts converge" do
        visit new_admin_reimbursements_expense_path

        assert_selector "[data-reimbursements-receipt-target='vatWarning']", visible: :hidden

        fill_in "Amount (£, incl. VAT)", with: "12.50"
        fill_in "Amount excl. VAT (£)", with: "12.50"
        assert_selector "[data-reimbursements-receipt-target='vatWarning']", visible: :visible

        # A real VAT breakdown puts the ex-VAT amount below the total.
        fill_in "Amount excl. VAT (£)", with: "10.42"
        assert_selector "[data-reimbursements-receipt-target='vatWarning']", visible: :hidden,
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
