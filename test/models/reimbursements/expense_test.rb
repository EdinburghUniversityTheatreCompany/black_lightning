require "test_helper"

module Reimbursements
  class ExpenseTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # Not `include ...url_helpers`: Minitest would collect route helpers named
    # test_* (test_access_admin_reimbursements_setting_path) as tests.
    def routes = Rails.application.routes.url_helpers

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

    # A PDF is representable (its first page renders), so it gets a thumbnail.
    # The signed id is a bearer token for ActiveStorage's permanent,
    # unauthenticated routes, so receipts are identified by blob id instead.
    test "a PDF receipt is wrapped with a first-page thumbnail, an inline URL and its blob id" do
      expense = attach_test_receipt(create_expense, filename: "invoice.pdf")

      receipt = expense.receipts.sole
      file = expense.receipt_files.sole
      blob_id = file.blob_id
      assert_kind_of Attachment, receipt
      assert_equal "invoice.pdf", receipt.filename
      assert_equal "application/pdf", receipt.content_type
      assert receipt.pdf?
      assert_not receipt.image?
      assert receipt.previewable?, "a PDF must offer a thumbnail preview"
      assert receipt.inline_viewable?, "a PDF renders in the browser's own viewer"
      assert_equal blob_id.to_s, receipt.attachment_id
      assert_equal routes.thumbnail_admin_reimbursements_expense_receipt_path(expense.record_id, blob_id),
                   receipt.preview_url
      assert_equal routes.inline_admin_reimbursements_expense_receipt_path(expense.record_id, blob_id), receipt.url
      assert_equal routes.download_admin_reimbursements_expense_receipt_path(expense.record_id, blob_id),
                   receipt.download_url
      [ receipt.url, receipt.download_url, receipt.preview_url ].each do |url|
        assert_not url.include?(file.signed_id), "a signed id leaked into #{url}"
        assert_not url.start_with?("/rails/active_storage")
      end
    end

    # Sheet music and Office documents are allowed but neither previewable nor
    # renderable.
    test "an unrenderable receipt has no thumbnail and is not inline viewable" do
      expense = attach_test_receipt(create_expense, filename: "score.mscz",
                                    content_type: "application/x-musescore", bytes: "PK\x03\x04")

      receipt = expense.receipts.sole
      assert_not receipt.previewable?
      assert_not receipt.inline_viewable?
      assert_nil receipt.preview_url
    end

    test "missing_completion_fields counts offloaded receipts as receipts" do
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

    # #receipts builds three route paths per file; the count is asked once per row.
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

    # --- The international rail ---------------------------------------------

    test "effective IBAN and BIC are the claim's own" do
      person = Person.create!(name: "Pat", email: "intl-payee@example.com")
      expense = create_expense(person: person, payment_method: Expense::PAYMENT_METHOD_INTERNATIONAL)

      assert_not expense.effective_has_bank_details?

      expense.update!(iban_override: " NL91ABNA0417164300 ", bic_override: "ABNANL2A")
      assert_equal "NL91ABNA0417164300", expense.effective_iban
      assert_equal "ABNANL2A", expense.effective_bic
      assert expense.effective_has_bank_details?
    end

    # Reading the wrong rail blocked every international claim at approval.
    test "effective_has_bank_details? reads the rail's own fields, not the other's" do
      person = Person.create!(name: "Pat", email: "rail-split@example.com")
      person.create_payment_details!(sort_code: "80-22-60", account_number: "12345678")
      expense = create_expense(person: person)

      assert expense.effective_has_bank_details?, "UK details satisfy the UK rail"

      expense.update!(payment_method: Expense::PAYMENT_METHOD_INTERNATIONAL)
      assert_not expense.effective_has_bank_details?,
                 "a sort code says nothing about where an international payment goes"

      expense.update!(iban_override: "DE89370400440532013000")
      assert_not expense.effective_has_bank_details?, "an IBAN with no BIC is not routable"

      expense.update!(bic_override: "DEUTDEFF500")
      assert expense.effective_has_bank_details?
    end

    test "the encrypted international overrides survive a round trip at full length" do
      # Both columns are string(255), which has to hold the ciphertext of the
      # longest allowed IBAN, not its plaintext.
      longest = "A" * BankDetails::IBAN_MAX_LENGTH
      expense = create_expense(payment_method: Expense::PAYMENT_METHOD_INTERNATIONAL,
                               iban_override: longest, bic_override: "DEUTDEFF500")

      assert_equal longest, expense.reload.iban_override
      assert_equal "DEUTDEFF500", expense.bic_override
    end

    # A foreign invoice carries no reclaimable UK VAT, so ex-VAT is the gross.
    test "an international claim's ex-VAT amount mirrors its GBP amount, a UK claim keeps its split" do
      amounts = { amount: BigDecimal("230.00"), amount_excl_vat: BigDecimal("191.67") }
      international = create_expense(payment_method: Expense::PAYMENT_METHOD_INTERNATIONAL, **amounts)
      uk = create_expense(**amounts)

      assert_equal BigDecimal("230.00"), international.reload.amount_excl_vat,
                   "a VAT split on a foreign invoice would deduct tax nobody can reclaim"
      assert_equal BigDecimal("191.67"), uk.reload.amount_excl_vat
    end

    test "editable? only for submitter types in Draft or Pending" do
      assert create_expense.editable?
      assert_not create_expense(status: Status::APPROVED).editable?
      assert_not create_expense(expense_type: Expense::TYPE_FROM_EUSA).editable?
    end

    test "status, expense_type and payment_method are validated against the known sets" do
      { status: "Bogus", expense_type: "Bogus", payment_method: "carrier_pigeon" }.each do |attr, value|
        assert_raises(ActiveRecord::RecordInvalid, attr.to_s) { create_expense(attr => value) }
      end
    end
  end
end
