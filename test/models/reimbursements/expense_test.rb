require "test_helper"

module Reimbursements
  # The AR Expense must keep the Airtable-era PORO's interface: string ids,
  # the receipts wrapper, completion checks and the effective money path.
  class ExpenseTest < ActiveSupport::TestCase
    def create_expense(**attrs)
      Expense.create!(status: Status::PENDING, description: "Gaffer tape", **attrs)
    end

    test "record_id and batch_id are opaque strings" do
      batch = Batch.create!(name: "BACS 2026-07-01")
      expense = create_expense(batch: batch)

      assert_equal expense.id.to_s, expense.record_id
      assert_equal batch.record_id, expense.batch_id
      assert_kind_of String, expense.batch_id
    end

    test "auto_number continues the sequence but respects explicit values" do
      first = create_expense(auto_number: 41)
      second = create_expense
      assert_equal 42, second.auto_number
      assert_equal 41, first.auto_number
    end

    test "sharepoint_receipt_urls splits the newline column into an array" do
      expense = create_expense
      expense.update!(sharepoint_receipt_urls: "https://sp/a.pdf\n https://sp/b.pdf \n\n")
      assert_equal %w[https://sp/a.pdf https://sp/b.pdf], expense.reload.sharepoint_receipt_urls
      assert_equal [], create_expense.sharepoint_receipt_urls
    end

    test "receipts wraps attached files into Attachment POROs" do
      expense = create_expense
      expense.receipt_files.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "receipt.pdf",
                                   content_type: "application/pdf")

      receipt = expense.receipts.sole
      assert_kind_of Attachment, receipt
      assert_equal "receipt.pdf", receipt.filename
      assert_equal "application/pdf", receipt.content_type
      assert receipt.attachment_id.present?
      assert_match %r{/rails/active_storage/blobs/}, receipt.url
      assert_not receipt.image?
    end

    test "missing_completion_fields mirrors the PORO, including offloaded receipts" do
      expense = create_expense
      missing = expense.missing_completion_fields
      assert_includes missing, "a budget"
      assert_includes missing, "the amount"
      assert_includes missing, "a receipt"

      budget = Budget.create!(name: "Props")
      expense.update!(budget: budget, amount: 12, amount_excl_vat: 10,
                      payment_reference: "PROPS1",
                      sharepoint_receipt_urls: "https://sp/a.pdf")
      assert_empty expense.reload.missing_completion_fields
      assert_not expense.needs_completion?
    end

    test "receipt_count honours offloaded receipts" do
      expense = create_expense(sharepoint_receipt_urls: "https://sp/a.pdf\nhttps://sp/b.pdf")
      assert_equal 2, expense.receipt_count
    end

    test "effective payee falls back through PaymentDetails" do
      person = Person.create!(name: "Pat", email: "payee@example.com")
      person.create_payment_details!(sort_code: "80-22-60", account_number: "12345678")
      budget = Budget.create!(name: "Props", nominal_code: "4000")
      expense = create_expense(person: person, budget: budget)

      assert_equal "Pat", expense.effective_payee_name
      assert_equal "80-22-60", expense.effective_sort_code
      assert_equal "12345678", expense.effective_account_number
      assert_equal "4000", expense.effective_nominal_code
      assert expense.effective_has_bank_details?

      expense.update!(payee_name_override: "Venue Ltd", sort_code_override: "11-22-33",
                      account_number_override: "87654321", nominal_code_override: "9999")
      assert expense.payee_override?
      assert_equal "Venue Ltd", expense.effective_payee_name
      assert_equal "11-22-33", expense.effective_sort_code
      assert_equal "87654321", expense.effective_account_number
      assert_equal "9999", expense.effective_nominal_code
    end

    test "editable? only for submitter types in Draft or Pending" do
      assert create_expense.editable?
      assert_not create_expense(status: Status::APPROVED).editable?
      assert_not create_expense(expense_type: Expense::TYPE_FROM_EUSA).editable?
    end

    test "ai_checked? only for genuine verdicts" do
      assert create_expense(ai_check_status: "pass").ai_checked?
      assert create_expense(ai_check_status: "fail").ai_checked?
      assert_not create_expense(ai_check_status: "error").ai_checked?
      assert_not create_expense.ai_checked?
    end

    test "status and expense_type are validated against the known sets" do
      assert_raises(ActiveRecord::RecordInvalid) { create_expense(status: "Bogus") }
      assert_raises(ActiveRecord::RecordInvalid) { create_expense(expense_type: "Bogus") }
    end
  end
end
