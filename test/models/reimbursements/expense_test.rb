require "test_helper"

module Reimbursements
  class ExpenseTest < ActiveSupport::TestCase
    def build_expense(**overrides)
      defaults = {
        record_id: "recExp1",
        auto_number: 7,
        person: Person.new(record_id: "recPer1", name: "Pat Producer", email: "pat@example.com"),
        amount: BigDecimal("12.50"),
        amount_excl_vat: BigDecimal("10.42"),
        budget: Budget.new(record_id: "recBud1", name: "Props", nominal_code: "4000"),
        description: "Fake blood, 2 litres",
        receipts: [ Attachment.new(attachment_id: "att1", filename: "receipt.pdf", url: "https://x", size_bytes: 100) ],
        status: Status::PENDING,
        payment_reference: "PROPS PAT"
      }
      Expense.new(**defaults.merge(overrides))
    end

    test "editable only while pending" do
      assert build_expense.editable?
      assert_not build_expense(status: Status::APPROVED).editable?
      assert_not build_expense(status: Status::REJECTED).editable?
    end

    test "complete expense does not need completion" do
      assert_not build_expense.needs_completion?
    end

    test "needs completion when required fields are missing" do
      assert build_expense(budget: nil).needs_completion?
      assert build_expense(payment_reference: "").needs_completion?
      assert build_expense(amount_excl_vat: nil).needs_completion?
      assert build_expense(receipts: []).needs_completion?
      assert build_expense(description: "").needs_completion?
    end

    test "missing_completion_fields names each absent required field" do
      assert_empty build_expense.missing_completion_fields
      assert_includes build_expense(amount_excl_vat: nil).missing_completion_fields, "the amount excluding VAT"
      assert_includes build_expense(payment_reference: "").missing_completion_fields, "a payment reference"
      assert_includes build_expense(receipts: []).missing_completion_fields, "a receipt"
      assert_includes build_expense(budget: nil).missing_completion_fields, "a budget"
      assert_equal 2, build_expense(amount_excl_vat: nil, receipts: []).missing_completion_fields.size
    end

    test "a SharePoint-offloaded receipt counts as present" do
      offloaded = build_expense(receipts: [], sharepoint_receipt_urls: [ "https://sp/receipt.pdf" ])
      assert_not_includes offloaded.missing_completion_fields, "a receipt"
      assert_not offloaded.needs_completion?
    end

    test "payee override detection" do
      assert_not build_expense.payee_override?
      assert build_expense(payee_name_override: "Stage Supplies Ltd").payee_override?
      assert build_expense(sort_code_override: "112233").payee_override?
    end

    test "status badge variants cover all statuses" do
      Status.all.each do |status|
        assert_kind_of Symbol, Status.badge_variant(status)
      end
    end

    test "person may be nil" do
      assert_nil build_expense(person: nil).person
    end

    # --- effective payee (the money path) ---------------------------------

    test "effective payee falls back to the linked person when no override" do
      expense = build_expense(
        person: Person.new(record_id: "recP", name: "Pat", email: "p@x", sort_code: "80-22-60",
                           account_number: "12345678")
      )
      assert_equal "Pat", expense.effective_payee_name
      assert_equal "80-22-60", expense.effective_sort_code
      assert_equal "12345678", expense.effective_account_number
      assert expense.effective_has_bank_details?
    end

    test "override wins over the linked person for the effective payee" do
      expense = build_expense(
        person: Person.new(record_id: "recP", name: "Pat", email: "p@x", sort_code: "80-22-60",
                           account_number: "12345678"),
        payee_name_override: "Stage Supplies Ltd",
        sort_code_override: "11-22-33",
        account_number_override: "87654321"
      )
      assert_equal "Stage Supplies Ltd", expense.effective_payee_name
      assert_equal "11-22-33", expense.effective_sort_code
      assert_equal "87654321", expense.effective_account_number
    end

    test "effective payee tolerates a nil person" do
      expense = build_expense(person: nil)
      assert_equal "", expense.effective_payee_name
      assert_equal "", expense.effective_sort_code
      assert_not expense.effective_has_bank_details?
    end

    test "effective has bank details is false when only one of sort/account is present" do
      expense = build_expense(
        person: Person.new(record_id: "recP", name: "Pat", email: "p@x", sort_code: "80-22-60",
                           account_number: "")
      )
      assert_not expense.effective_has_bank_details?
    end

    test "effective nominal code uses the override then the budget" do
      assert_equal "4000", build_expense.effective_nominal_code
      assert_equal "9999", build_expense(nominal_code_override: "9999").effective_nominal_code
      assert_equal "", build_expense(budget: nil).effective_nominal_code
    end

    test "attachment previews fall back to the full image while airtable's thumbnail is pending" do
      fresh_image = Attachment.new(attachment_id: "att1", filename: "r.png", url: "https://full",
                                   content_type: "image/png")
      thumbed = Attachment.new(attachment_id: "att2", filename: "r.png", url: "https://full",
                               content_type: "image/png", thumbnail_url: "https://thumb")
      pdf = Attachment.new(attachment_id: "att3", filename: "r.pdf", url: "https://full",
                           content_type: "application/pdf")

      assert_equal "https://full", fresh_image.preview_url
      assert_equal "https://thumb", thumbed.preview_url
      assert_nil pdf.preview_url
      assert_not pdf.image?
    end
  end
end
