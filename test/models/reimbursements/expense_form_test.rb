require "test_helper"

module Reimbursements
  class ExpenseFormTest < ActiveSupport::TestCase
    def upload
      Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/reimbursements_receipt.pdf"), "application/pdf"
      )
    end

    def build_form(**attrs)
      defaults = {
        amount: "12.50", amount_excl_vat: "10.42", budget_record_id: "recBud1",
        description: "Fake blood", payment_reference: "PROPS PAT",
        receipts: [ upload ]
      }
      ExpenseForm.new(defaults.merge(attrs))
    end

    test "valid with the full set of required fields" do
      form = build_form
      assert form.valid?, form.errors.full_messages.to_sentence
      assert_equal BigDecimal("12.50"), form.amount_decimal
    end

    test "parses currency-formatted amounts" do
      # Over the large-amount threshold, so it also needs the acknowledgement.
      form = build_form(amount: "£1,234.56", amount_excl_vat: "£1,028.80", large_amount_acknowledged: "1")
      assert form.valid?, form.errors.full_messages.to_sentence
      assert_equal BigDecimal("1234.56"), form.amount_decimal
    end

    test "large-amount soft block requires acknowledgement at or above the threshold" do
      form = build_form(amount: "1000.00", amount_excl_vat: "900.00")
      assert_not form.valid?
      assert form.errors[:large_amount_acknowledged].present?, "£1000 must ask for confirmation"

      acknowledged = build_form(amount: "1000.00", amount_excl_vat: "900.00",
                                large_amount_acknowledged: "1")
      assert acknowledged.valid?, acknowledged.errors.full_messages.to_sentence
    end

    test "an ordinary-sized claim needs no large-amount acknowledgement" do
      assert build_form(amount: "999.99", amount_excl_vat: "900.00").valid?
    end

    test "a large draft is exempt from the soft block (drafts accept gaps)" do
      assert build_form(amount: "5000.00", save_as_draft: "1").valid?
    end

    test "requires all the airtable form's required fields" do
      form = ExpenseForm.new
      assert_not form.valid?
      %i[amount amount_excl_vat budget_record_id description payment_reference receipts].each do |field|
        assert form.errors[field].present?, "expected error on #{field}"
      end
    end

    test "error messages use human attribute names, not humanized internal ones" do
      form = ExpenseForm.new
      form.valid?
      messages = form.errors.full_messages
      # "Budget", not "Budget record"; "Amount excl. VAT", not "Amount excl vat".
      assert messages.any? { |m| m.start_with?("Budget must") }, messages.inspect
      assert_not messages.any? { |m| m.include?("Budget record") }, "internal attribute name leaked"
      assert messages.any? { |m| m.start_with?("Amount excl. VAT must") }, messages.inspect
    end

    test "rejects non-positive amounts and excl above total" do
      assert_not build_form(amount: "0").valid?
      assert_not build_form(amount: "-5").valid?
      assert_not build_form(amount_excl_vat: "13.00").valid?
    end

    test "payment reference is limited to 18 characters" do
      assert_not build_form(payment_reference: "X" * 19).valid?
      assert build_form(payment_reference: "X" * 18).valid?
    end

    # The only trigger left: an ex-VAT amount that isn't below the total means
    # the receipt showed no VAT breakdown, so the full amount hits the budget.
    test "vat soft block requires acknowledgement when excl equals total" do
      form = build_form(amount_excl_vat: "12.50")
      assert_not form.valid?
      assert form.errors[:vat_acknowledged].present?

      acknowledged = build_form(amount_excl_vat: "12.50", vat_acknowledged: "1")
      assert acknowledged.valid?, acknowledged.errors.full_messages.to_sentence
    end

    # An ex-VAT amount ABOVE the total trips the soft block too, but that state
    # is unreachable for a submitter: amounts_valid rejects it outright. Assert
    # the hard error is what actually governs, so nobody later "fixes" this into
    # a soft block that lets a nonsense pair through on one tick.
    test "excl above the total is a hard error, not merely a vat soft block" do
      form = build_form(amount_excl_vat: "20.00")
      assert_not form.valid?
      assert form.errors[:amount_excl_vat].present?

      acknowledged = build_form(amount_excl_vat: "20.00", vat_acknowledged: "1")
      assert_not acknowledged.valid?, "acknowledging VAT must not clear an impossible amount pair"
      assert acknowledged.errors[:amount_excl_vat].present?
    end

    test "no vat block when excl is below total" do
      assert build_form.valid?
    end

    test "on edit, the expense's existing receipts satisfy the requirement" do
      form = build_form(receipts: [], require_receipts: false, expense_receipt_count: 1)
      assert form.valid?, form.errors.full_messages.to_sentence
    end

    test "on edit, submitting a receipt-less expense points at the gallery" do
      form = build_form(receipts: [], require_receipts: false, expense_receipt_count: 0)
      assert_not form.valid?
      assert_includes form.errors[:base].sole, "receipts section"
    end

    test "rejects disallowed receipt types" do
      # An executable disguised with a .pdf filename and a declared PDF
      # content_type: content-type validation is now based on the actual
      # bytes (Marcel), not the declared/filename-implied type alone, so this
      # must be caught by what the file really is.
      bad = Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/disguised_executable.pdf"), "application/pdf"
      )
      assert_not build_form(receipts: [ bad ]).valid?
    end

    test "accepts an iPhone HEIC photo and hands the controller the converted JPEG" do
      heic = Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/reimbursements_receipt.heic"), "image/heic"
      )
      form = build_form(receipts: [ heic ])

      assert form.valid?, form.errors.full_messages.to_sentence
      assert_equal [ { filename: "reimbursements_receipt.jpg", content_type: "image/jpeg" } ],
                   form.usable_receipts.map { |receipt| receipt.except(:bytes) }
    end

    test "an unreadable photo is a validation error, not an exception" do
      truncated = Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/truncated_receipt.heic"), "image/heic"
      )
      form = build_form(receipts: [ truncated ])

      assert_not form.valid?
      assert_match(/couldn't read truncated_receipt\.heic/, form.errors[:receipts].sole)
      assert_empty form.usable_receipts
    end

    test "an oversized file is rejected by size without being read for content-type sniffing" do
      oversized = Object.new
      def oversized.size = ExpenseForm::MAX_RECEIPT_BYTES + 1
      def oversized.original_filename = "huge.pdf"
      def oversized.content_type = "application/pdf"
      def oversized.read = raise("must not read an oversized file just to sniff its type")

      form = build_form(receipts: [ oversized ])

      assert_not form.valid?
      assert_includes form.errors[:receipts], "huge.pdf must be 5 MB or smaller."
    end

    test "validates override formats only when present" do
      all_three = { payee_name_override: "Stage Supplies Ltd", sort_code_override: "80-22-60",
                   account_number_override: "12345678" }
      assert build_form(**all_three).valid?
      assert_not build_form(**all_three.merge(sort_code_override: "80-2")).valid?
      assert_not build_form(**all_three.merge(account_number_override: "123")).valid?
    end

    test "requires all three overrides together, not just one or two (prevents a spliced payee)" do
      partial = build_form(payee_name_override: "Stage Supplies Ltd")
      assert_not partial.valid?
      assert_includes partial.errors[:base].join, "fill in all three"

      assert_not build_form(sort_code_override: "80-22-60", account_number_override: "12345678").valid?

      assert build_form(payee_name_override: "Stage Supplies Ltd", sort_code_override: "80-22-60",
                        account_number_override: "12345678").valid?
      # Blank on all three (the common case: no override at all) is still fine.
      assert build_form.valid?
    end

    # An Invoice means EUSA pays the supplier directly. Without the overrides the
    # effective payee silently falls back to the SUBMITTER's own bank details,
    # which review can't catch (effective_has_bank_details? is satisfied), so the
    # portal would BACS-pay the producer for a bill they never paid.
    test "an invoice requires the third-party payee trio to submit" do
      form = build_form(expense_type: Expense::TYPE_INVOICE)

      assert_not form.valid?
      assert_includes form.errors[:base].join, "Reimbursement",
                      "the error must point at the type to pick when they paid it themselves"
    end

    test "an invoice with the full payee trio submits" do
      form = build_form(expense_type: Expense::TYPE_INVOICE,
                        payee_name_override: "Stage Supplies Ltd",
                        sort_code_override: "80-22-60", account_number_override: "12345678")

      assert form.valid?, form.errors.full_messages.to_sentence
    end

    test "a partly-filled invoice trio reports the all-or-nothing rule once, not twice" do
      form = build_form(expense_type: Expense::TYPE_INVOICE,
                        payee_name_override: "Stage Supplies Ltd")

      assert_not form.valid?
      assert_equal 1, form.errors[:base].size, form.errors[:base].inspect
      assert_includes form.errors[:base].sole, "fill in all three"
    end

    test "an invoice DRAFT still saves without payee details (gaps are completed later)" do
      form = build_form(expense_type: Expense::TYPE_INVOICE, save_as_draft: "1")

      assert form.valid?, form.errors.full_messages.to_sentence
    end

    test "a reimbursement needs no payee override" do
      assert build_form(expense_type: Expense::TYPE_REIMBURSEMENT).valid?
    end

    # from_actual's internal type is finance recording an already-settled EUSA
    # cost; there is no third party to pay and no overrides to demand.
    test "the internal From-EUSA type is not caught by the invoice rule" do
      form = ExpenseForm.from_actual(build_actual)
      form.budget_record_id = "recBud1"

      assert form.valid?, form.errors.full_messages.to_sentence
    end

    test "create_attrs carries person, pending status and normalized values" do
      attrs = build_form.create_attrs("recPer1")
      assert_equal "recPer1", attrs[:person_record_id]
      assert_equal Status::PENDING, attrs[:status]
      assert_equal BigDecimal("12.50"), attrs[:amount]
      assert_equal "", attrs[:payee_name_override], "blank overrides write empty strings so clearing them clears Airtable"
    end

    test "save_as_draft relaxes presence rules and writes Draft status" do
      form = ExpenseForm.new(save_as_draft: "1", receipts: [ upload ])
      assert form.valid?, form.errors.full_messages.to_sentence
      assert_equal Status::DRAFT, form.update_attrs[:status]

      submitted = ExpenseForm.new(receipts: [ upload ])
      assert_not submitted.valid?
    end

    test "draft still rejects malformed values that are present" do
      assert_not ExpenseForm.new(save_as_draft: "1", amount: "-5").valid?
      assert_not ExpenseForm.new(save_as_draft: "1", sort_code_override: "80-2").valid?
    end

    test "parses a comma decimal separator without a 100x blowup" do
      form = build_form(amount: "12,50", amount_excl_vat: "10,42")
      assert form.valid?, form.errors.full_messages.to_sentence
      assert_equal BigDecimal("12.50"), form.amount_decimal
      assert_equal BigDecimal("10.42"), form.amount_excl_vat_decimal
    end

    test "override bank details are formatted for storage" do
      attrs = build_form(sort_code_override: "112233", account_number_override: "1234 5678").update_attrs
      assert_equal "11-22-33", attrs[:sort_code_override]
      assert_equal "12345678", attrs[:account_number_override]
    end

    # --- from_actual (converting an imported EUSA row) ----------------------

    def build_actual(**attrs)
      defaults = { nominal_code: "431580", narrative: "Room hire recharge", ref: "J000001234",
                   debit: BigDecimal("42.00"), date: Date.new(2026, 5, 13) }
      EusaActual.new(**defaults.merge(attrs))
    end

    test "from_actual prefills the internal From-EUSA type from the ledger row" do
      form = ExpenseForm.from_actual(build_actual)

      assert_equal Expense::TYPE_FROM_EUSA, form.expense_type
      assert_equal BigDecimal("42.00"), form.amount_decimal
      assert_equal BigDecimal("42.00"), form.amount_excl_vat_decimal
      assert_equal "Room hire recharge", form.description
      assert_equal "J000001234", form.payment_reference
      assert_not form.require_receipts?, "a cost EUSA levied directly has no receipt to attach"
    end

    # A From-EUSA line has no receipt and no VAT breakdown, and can easily run
    # into four figures: the submitter-facing soft blocks would only get in the
    # way of recording an already-settled cost.
    test "from_actual needs no receipt, VAT tick or large-amount tick" do
      form = ExpenseForm.from_actual(build_actual(debit: BigDecimal("5000.00")))
      form.budget_record_id = "recBud1"

      assert form.valid?, form.errors.full_messages.to_sentence
    end

    test "from_actual still requires a budget, a description and a reference" do
      form = ExpenseForm.from_actual(build_actual(narrative: "", ref: ""))

      assert_not form.valid?
      %i[budget_record_id description payment_reference].each do |field|
        assert form.errors[field].present?, "expected error on #{field}"
      end
    end

    test "from_actual truncates an over-long reference to what EUSA accepts" do
      form = ExpenseForm.from_actual(build_actual(ref: "J0000012345678901234567890"))

      assert_equal ExpenseForm::REFERENCE_LIMIT, form.payment_reference.length
      form.budget_record_id = "recBud1"
      assert form.valid?, form.errors.full_messages.to_sentence
    end

    # The relaxations ride on an internal flag the producer form never permits,
    # so a submitter can't pick the internal type to dodge the receipt rule.
    test "a submitted expense_type of From EUSA is still rejected on the producer form" do
      form = ExpenseForm.new(expense_type: Expense::TYPE_FROM_EUSA, amount: "10.00",
                             amount_excl_vat: "10.00", budget_record_id: "recBud1",
                             description: "x", payment_reference: "y")

      assert_not form.valid?
      assert form.errors[:expense_type].present?
      assert form.errors[:receipts].present?, "and it still has to carry a receipt"
    end

    # --- The international rail ---------------------------------------------

    def international_params(**overrides)
      {
        payment_method: Reimbursements::Expense::PAYMENT_METHOD_INTERNATIONAL,
        foreign_amount: "266.69", budget_record_id: "recBudget1",
        description: "Festival insurance", payment_reference: "INSURANCE",
        payee_name_override: "Ausland GmbH",
        iban_override: "DE89 3704 0044 0532 0130 00", bic_override: "deutdeff500",
        require_receipts: false, expense_receipt_count: 1
      }.merge(overrides)
    end

    test "an international claim submits on the foreign amount alone" do
      # The submitter knows what the invoice says and nothing about the rate
      # EUSA's bank will get. Finance enters the GBP figure at review, and
      # cannot approve without it.
      form = ExpenseForm.new(international_params)

      assert form.valid?, form.errors.full_messages.inspect
      assert_nil form.update_attrs[:amount]
    end

    test "a missing foreign amount is refused" do
      form = ExpenseForm.new(international_params(foreign_amount: ""))

      assert_not form.valid?
      assert form.errors[:foreign_amount].present?
    end

    test "the IBAN is mod-97 checked, not merely shaped" do
      form = ExpenseForm.new(international_params(iban_override: "DE88 3704 0044 0532 0130 00"))

      assert_not form.valid?
      assert form.errors[:iban_override].present?
    end

    test "a malformed BIC is refused" do
      form = ExpenseForm.new(international_params(bic_override: "DEUTDEFF5"))

      assert_not form.valid?
      assert form.errors[:bic_override].present?
    end

    # Nobody on file has an IBAN, so falling back to the submitter's own
    # details would leave the form with nothing to send.
    test "an international claim always needs the payee trio" do
      form = ExpenseForm.new(international_params(payee_name_override: "", iban_override: "",
                                                  bic_override: ""))

      assert_not form.valid?
      assert form.errors[:base].any? { |e| e.include?("payee's own bank") }
    end

    test "a partly-filled international trio reports the all-or-nothing message" do
      form = ExpenseForm.new(international_params(bic_override: ""))

      assert_not form.valid?
      assert form.errors[:base].any? { |e| e.include?("all three") }
    end

    test "the IBAN and BIC are normalised on the way through" do
      attrs = ExpenseForm.new(international_params).update_attrs

      assert_equal "DE89370400440532013000", attrs[:iban_override]
      assert_equal "DEUTDEFF500", attrs[:bic_override]
      assert_equal Reimbursements::Expense::CURRENCY_EUR, attrs[:foreign_currency]
    end

    test "a UK claim stores no currency" do
      attrs = build_form.update_attrs

      assert_nil attrs[:foreign_currency]
      assert_equal Reimbursements::Expense::PAYMENT_METHOD_UK_BACS, attrs[:payment_method]
    end

    # The guard exists to catch pence typed as pounds; reading the GBP field,
    # which an international submitter never fills in, would switch it off for
    # exactly the claims whose figures nobody has checked yet.
    test "the large-amount confirmation reads the foreign amount" do
      form = ExpenseForm.new(international_params(foreign_amount: "5000"))

      assert_not form.valid?
      assert form.errors[:large_amount_acknowledged].present?

      confirmed = ExpenseForm.new(international_params(foreign_amount: "5000",
                                                       large_amount_acknowledged: "1"))
      assert confirmed.valid?, confirmed.errors.full_messages.inspect
    end

    test "the VAT soft block never fires on an international claim" do
      # There is no ex-VAT figure to compare: a foreign invoice carries no
      # reclaimable UK VAT.
      form = ExpenseForm.new(international_params)

      assert form.valid?, form.errors.full_messages.inspect
      assert_empty form.errors[:vat_acknowledged]
    end

    test "a draft international claim saves incomplete" do
      form = ExpenseForm.new(international_params(foreign_amount: "", payee_name_override: "",
                                                  iban_override: "", bic_override: "",
                                                  save_as_draft: "1"))

      assert form.valid?, form.errors.full_messages.inspect
    end

    test "from_expense round-trips the international fields" do
      expense = Expense.new(
        payment_method: Expense::PAYMENT_METHOD_INTERNATIONAL,
        foreign_amount: BigDecimal("266.69"), foreign_currency: Expense::CURRENCY_EUR,
        iban_override: "DE89370400440532013000", bic_override: "DEUTDEFF500"
      )
      form = ExpenseForm.from_expense(expense)

      assert form.international?
      assert_equal "266.69", form.foreign_amount
      assert_equal "DE89370400440532013000", form.iban_override
      assert_equal "DEUTDEFF500", form.bic_override
    end
  end
end
