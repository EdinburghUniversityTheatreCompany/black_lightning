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

    # A PDF receipt is representable (poppler/mupdf render its first page), so
    # the wrapper must carry a thumbnail: the strip draws a real first-page
    # preview instead of a generic document icon.
    test "a PDF receipt is wrapped with a first-page thumbnail and an inline URL" do
      expense = create_expense
      expense.receipt_files.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "invoice.pdf",
                                   content_type: "application/pdf")

      receipt = expense.receipts.sole
      assert receipt.pdf?
      assert receipt.previewable?, "a PDF must offer a thumbnail preview"
      assert_match %r{/rails/active_storage/representations/}, receipt.preview_url
      assert receipt.inline_viewable?, "a PDF renders in the browser's own viewer"
      # Proxied + inline so the <iframe> stays same-origin and is not downloaded.
      assert_match %r{/rails/active_storage/blobs/proxy/}, receipt.inline_url
      assert_match(/disposition=inline/, receipt.inline_url)
      # The viewer's Download link must save the file even for a type the browser
      # would happily display, and even when the URL redirects to the storage host.
      assert_match(/disposition=attachment/, receipt.download_url)
    end

    # Sheet music and Office documents are in Attachment::ALLOWED_CONTENT_TYPES
    # but are neither representable nor renderable, so the viewer has to fall
    # back to the document icon plus a download link.
    test "an unrenderable receipt has no thumbnail and is not inline viewable" do
      expense = create_expense
      expense.receipt_files.attach(io: StringIO.new("PK"), filename: "score.mscz",
                                   content_type: "application/x-musescore")

      receipt = expense.receipts.sole
      assert_not receipt.previewable?
      assert_not receipt.inline_viewable?
      assert_nil receipt.preview_url
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

    # #receipts wraps each attachment in an Attachment value object, minting a signed id, a
    # blob path and a variant representation path apiece. The batch builder and the
    # expense-edit screen ask for the COUNT once per row, so counting must not pay for that.
    test "receipt_count counts attachments without building the receipt wrappers" do
      expense = create_expense
      expense.receipt_files.attach(io: File.open(Rails.root.join("test", "test.png")),
                                   filename: "receipt.png", content_type: "image/png")

      assert_equal 1, expense.receipt_count
      assert_nil expense.instance_variable_get(:@receipts),
                 "counting receipts must not build the Attachment wrappers"
      assert_empty expense.missing_completion_fields.grep(/receipt/)
      assert_nil expense.instance_variable_get(:@receipts),
                 "the completeness check must not build them either"
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


    test "status and expense_type are validated against the known sets" do
      assert_raises(ActiveRecord::RecordInvalid) { create_expense(status: "Bogus") }
      assert_raises(ActiveRecord::RecordInvalid) { create_expense(expense_type: "Bogus") }
    end
  end
end
