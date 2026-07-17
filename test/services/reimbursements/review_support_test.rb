require "test_helper"
require "bigdecimal"

module Reimbursements
  # Ported from bedlam-bacs tests/test_review_helpers.py (needs_attention,
  # auto_payment_reference, find_duplicate_submissions). send_rejection_notification
  # ports with the Review UI (it needs Graph/mailer).
  class ReviewSupportTest < ActiveSupport::TestCase
    # Records the (sort, account) it was asked to check and returns a preset result.
    class FakeChecker
      attr_reader :calls

      def initialize(result)
        @result = result
        @calls = []
      end

      def check(sort_code, account_number)
        @calls << [ sort_code, account_number ]
        @result
      end
    end

    def valid_payee
      Person.new(record_id: "recPerson1", name: "Alice Producer", email: "alice@example.com",
        sort_code: "12-34-56", account_number: "12345678")
    end

    def payee_without_bank
      Person.new(record_id: "recPerson2", name: "Bob NoBank", email: "bob@example.com",
        sort_code: "", account_number: "")
    end

    def budget(remaining: BigDecimal("500.00"), nominal_code: "439999", record_id: "recBudget1")
      Budget.new(record_id: record_id, name: "Production", nominal_code: nominal_code, remaining: remaining)
    end

    def receipt
      Attachment.new(attachment_id: "att1", filename: "receipt.pdf",
        url: "https://example.com/receipt.pdf", size_bytes: 1024)
    end

    def expense(payee:, budget:, amount_excl_vat: BigDecimal("50.00"), receipts: [], **extra)
      Expense.new(record_id: "recExpense1", auto_number: 1, status: Status::PENDING,
        person: payee, amount: BigDecimal("60.00"), amount_excl_vat: amount_excl_vat,
        budget: budget, description: "Test expense", receipts: receipts, **extra)
    end

    def valid_checker
      FakeChecker.new(ModulusCheck::VALID)
    end

    # --- needs_attention: gross amount -------------------------------------

    test "nil gross amount needs attention" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [ receipt ], amount: nil)
      assert ReviewSupport.needs_attention(exp, { "recBudget1" => budget }, valid_checker)
    end

    test "zero gross amount needs attention" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [ receipt ], amount: BigDecimal("0"))
      assert ReviewSupport.needs_attention(exp, { "recBudget1" => budget }, valid_checker)
    end

    # --- needs_attention: amount_excl_vat ---------------------------------

    test "nil ex-VAT amount needs attention" do
      exp = expense(payee: valid_payee, budget: budget, amount_excl_vat: nil, receipts: [ receipt ])
      assert ReviewSupport.needs_attention(exp, { "recBudget1" => budget }, valid_checker)
    end

    test "zero ex-VAT amount needs attention" do
      exp = expense(payee: valid_payee, budget: budget, amount_excl_vat: BigDecimal("0"), receipts: [ receipt ])
      assert ReviewSupport.needs_attention(exp, { "recBudget1" => budget }, valid_checker)
    end

    test "positive ex-VAT amount does not trigger" do
      exp = expense(payee: valid_payee, budget: budget, amount_excl_vat: BigDecimal("50.00"), receipts: [ receipt ])
      assert_not ReviewSupport.needs_attention(exp, { "recBudget1" => budget }, valid_checker)
    end

    # --- needs_attention: receipts ----------------------------------------

    test "no receipts needs attention" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [])
      assert ReviewSupport.needs_attention(exp, { "recBudget1" => budget }, valid_checker)
    end

    # --- needs_attention: modulus -----------------------------------------

    test "invalid modulus needs attention" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [ receipt ])
      assert ReviewSupport.needs_attention(exp, { "recBudget1" => budget }, FakeChecker.new(ModulusCheck::INVALID))
    end

    test "outside spec modulus does not need attention" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [ receipt ])
      assert_not ReviewSupport.needs_attention(exp, { "recBudget1" => budget }, FakeChecker.new(ModulusCheck::OUTSIDE_SPEC))
    end

    # --- needs_attention: bank details ------------------------------------

    test "no effective bank details needs attention" do
      exp = expense(payee: payee_without_bank, budget: budget, receipts: [ receipt ])
      assert ReviewSupport.needs_attention(exp, { "recBudget1" => budget }, valid_checker)
    end

    # --- needs_attention: over budget -------------------------------------

    # Gross tracks the ex-VAT figure so these isolate the over-budget check
    # (a gross far below the ex-VAT would trip the ex-VAT-over-gross flag instead).
    test "over budget needs attention" do
      exp = expense(payee: valid_payee, budget: budget, amount: BigDecimal("600.00"),
                    amount_excl_vat: BigDecimal("600.00"), receipts: [ receipt ])
      assert ReviewSupport.needs_attention(exp, { "recBudget1" => budget }, valid_checker)
    end

    test "exactly at remaining does not trigger" do
      exp = expense(payee: valid_payee, budget: budget, amount: BigDecimal("500.00"),
                    amount_excl_vat: BigDecimal("500.00"), receipts: [ receipt ])
      assert_not ReviewSupport.needs_attention(exp, { "recBudget1" => budget }, valid_checker)
    end

    test "nil remaining does not trigger over-budget" do
      no_remaining = budget(remaining: nil, nominal_code: "439000", record_id: "recBudget2")
      exp = expense(payee: valid_payee, budget: no_remaining, amount: BigDecimal("9999.00"),
                    amount_excl_vat: BigDecimal("9999.00"), receipts: [ receipt ])
      assert_not ReviewSupport.needs_attention(exp, { "recBudget2" => no_remaining }, valid_checker)
    end

    test "budget not in lookup does not trigger over-budget" do
      exp = expense(payee: valid_payee, budget: budget, amount: BigDecimal("9999.00"),
                    amount_excl_vat: BigDecimal("9999.00"), receipts: [ receipt ])
      assert_not ReviewSupport.needs_attention(exp, {}, valid_checker)
    end

    # --- needs_attention: ex-VAT exceeds gross ----------------------------

    test "ex-VAT amount above the gross is an advisory flag" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [ receipt ],
                    amount: BigDecimal("50.00"), amount_excl_vat: BigDecimal("55.00"))
      summary = ReviewSupport.attention_summary(exp, { "recBudget1" => budget }, valid_checker)
      assert_empty summary[:blocking]
      assert_includes summary[:advisory], "ex-VAT amount exceeds the gross"
    end

    test "ex-VAT equal to the gross does not flag" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [ receipt ],
                    amount: BigDecimal("50.00"), amount_excl_vat: BigDecimal("50.00"))
      summary = ReviewSupport.attention_summary(exp, { "recBudget1" => budget }, valid_checker)
      assert_not_includes summary[:advisory], "ex-VAT amount exceeds the gross"
    end

    # --- needs_attention: missing budget ----------------------------------

    test "missing budget (nil) needs attention" do
      exp = expense(payee: valid_payee, budget: nil, receipts: [ receipt ])
      assert ReviewSupport.needs_attention(exp, {}, valid_checker)
    end

    test "blank-record-id budget needs attention" do
      placeholder = Budget.new(record_id: "", name: "(missing budget)", nominal_code: "")
      exp = expense(payee: valid_payee, budget: placeholder, receipts: [ receipt ])
      assert ReviewSupport.needs_attention(exp, {}, valid_checker)
    end

    # --- needs_attention: payee override uses effective details -----------

    test "modulus runs on the override account, not the empty linked payee" do
      exp = expense(payee: payee_without_bank, budget: budget, receipts: [ receipt ],
        payee_name_override: "Carol Supplier", sort_code_override: "12-34-56",
        account_number_override: "12345678")
      checker = valid_checker
      assert_not ReviewSupport.needs_attention(exp, { "recBudget1" => budget }, checker)
      assert_equal [ [ "12-34-56", "12345678" ] ], checker.calls
    end

    test "invalid override account needs attention" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [ receipt ],
        sort_code_override: "12-34-56", account_number_override: "00000000")
      checker = FakeChecker.new(ModulusCheck::INVALID)
      assert ReviewSupport.needs_attention(exp, { "recBudget1" => budget }, checker)
      assert_equal [ [ "12-34-56", "00000000" ] ], checker.calls
    end

    # --- needs_attention_reasons ------------------------------------------

    test "a clean expense has no attention reasons" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [ receipt ])
      assert_empty ReviewSupport.needs_attention_reasons(exp, { "recBudget1" => budget }, valid_checker)
    end

    test "reasons name a missing ex-VAT amount" do
      exp = expense(payee: valid_payee, budget: budget, amount_excl_vat: nil, receipts: [ receipt ])
      assert_includes ReviewSupport.needs_attention_reasons(exp, { "recBudget1" => budget }, valid_checker), "no ex-VAT amount"
    end

    test "reasons name a missing budget" do
      exp = expense(payee: valid_payee, budget: nil, receipts: [ receipt ])
      assert_includes ReviewSupport.needs_attention_reasons(exp, {}, valid_checker), "no budget"
    end

    test "reasons name a missing receipt" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [])
      assert_includes ReviewSupport.needs_attention_reasons(exp, { "recBudget1" => budget }, valid_checker), "no receipt"
    end

    test "an offloaded SharePoint receipt is not flagged as missing" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [],
        sharepoint_receipt_urls: [ "https://sp/receipt.pdf" ])
      reasons = ReviewSupport.needs_attention_reasons(exp, { "recBudget1" => budget }, valid_checker)
      assert_not_includes reasons, "no receipt"
      assert_empty reasons
    end

    test "reasons name missing bank details and skip the modulus check" do
      exp = expense(payee: payee_without_bank, budget: budget, receipts: [ receipt ])
      checker = valid_checker
      reasons = ReviewSupport.needs_attention_reasons(exp, { "recBudget1" => budget }, checker)
      assert_includes reasons, "no bank details"
      assert_not_includes reasons, "failed the bank modulus check"
      assert_empty checker.calls
    end

    test "reasons name a failed modulus check" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [ receipt ])
      reasons = ReviewSupport.needs_attention_reasons(exp, { "recBudget1" => budget }, FakeChecker.new(ModulusCheck::INVALID))
      assert_includes reasons, "failed the bank modulus check"
    end

    test "an outside-spec modulus is not named a failure" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [ receipt ])
      reasons = ReviewSupport.needs_attention_reasons(exp, { "recBudget1" => budget }, FakeChecker.new(ModulusCheck::OUTSIDE_SPEC))
      assert_not_includes reasons, "failed the bank modulus check"
    end

    test "reasons name an over-budget expense" do
      exp = expense(payee: valid_payee, budget: budget, amount_excl_vat: BigDecimal("600.00"), receipts: [ receipt ])
      assert_includes ReviewSupport.needs_attention_reasons(exp, { "recBudget1" => budget }, valid_checker), "over budget"
    end

    test "reasons collect every failing check at once" do
      exp = expense(payee: payee_without_bank, budget: nil, amount_excl_vat: nil, receipts: [])
      reasons = ReviewSupport.needs_attention_reasons(exp, {}, valid_checker)
      assert_includes reasons, "no ex-VAT amount"
      assert_includes reasons, "no budget"
      assert_includes reasons, "no receipt"
      assert_includes reasons, "no bank details"
    end

    test "needs_attention is true exactly when there are reasons" do
      clean = expense(payee: valid_payee, budget: budget, receipts: [ receipt ])
      assert_not ReviewSupport.needs_attention(clean, { "recBudget1" => budget }, valid_checker)
      dirty = expense(payee: valid_payee, budget: budget, receipts: [])
      assert ReviewSupport.needs_attention(dirty, { "recBudget1" => budget }, valid_checker)
    end

    # --- auto_payment_reference -------------------------------------------

    test "normal budget name returned as-is" do
      assert_equal "Production", ReviewSupport.auto_payment_reference("Production")
    end

    test "name truncated to 18 characters" do
      result = ReviewSupport.auto_payment_reference("A very long budget name that exceeds limit")
      assert_equal 18, result.length
      assert_equal "A very long budget", result
    end

    test "special chars stripped before truncation" do
      assert_equal "Show  Tell", ReviewSupport.auto_payment_reference("Show & Tell")
    end

    test "colon and bang stripped and truncated" do
      result = ReviewSupport.auto_payment_reference("Budget: 100 production costs!")
      refute_includes result, ":"
      refute_includes result, "!"
      assert_operator result.length, :<=, 18
    end

    test "hyphens are kept" do
      assert_equal "Tech-Theatre", ReviewSupport.auto_payment_reference("Tech-Theatre")
    end

    test "leading/trailing whitespace stripped from result" do
      assert_equal "Production", ReviewSupport.auto_payment_reference("  Production  ")
      assert_equal "Production", ReviewSupport.auto_payment_reference("@ Production")
    end

    test "truncation after stripping a leading unsafe char" do
      assert_equal "A very long name t", ReviewSupport.auto_payment_reference("!A very long name that exceeds")
    end

    test "empty name returns empty" do
      assert_equal "", ReviewSupport.auto_payment_reference("")
    end

    test "all special chars returns empty" do
      assert_equal "", ReviewSupport.auto_payment_reference("@#$%^&*()")
    end

    test "exactly 18 chars unchanged" do
      assert_equal "Exactly18CharsLong", ReviewSupport.auto_payment_reference("Exactly18CharsLong")
    end

    test "numbers kept" do
      assert_equal "Budget 2026", ReviewSupport.auto_payment_reference("Budget 2026")
    end

    test "pound sign stripped" do
      assert_equal "100 Budget", ReviewSupport.auto_payment_reference("£100 Budget")
    end

    # --- find_duplicate_submissions ---------------------------------------

    NOW = Time.utc(2026, 7, 9)

    def dup_expense(record_id, payee, amount:, auto_number:, submitted_at:)
      Expense.new(record_id: record_id, auto_number: auto_number, status: Status::PENDING,
        person: payee, amount: BigDecimal(amount), amount_excl_vat: BigDecimal(amount),
        budget: Budget.new(record_id: "recBudget1", name: "Production", nominal_code: "439999"),
        description: "Test expense", receipts: [], submitted_at: submitted_at)
    end

    def pair(payee_a, payee_b, amount_a: "60.00", amount_b: "60.00", gap_days: 0)
      a = dup_expense("recA", payee_a, amount: amount_a, auto_number: 1, submitted_at: NOW)
      b = dup_expense("recB", payee_b, amount: amount_b, auto_number: 2, submitted_at: NOW - gap_days.days)
      [ a, b ]
    end

    test "same payee, same amount, within window flagged" do
      a, b = pair(valid_payee, valid_payee, gap_days: 5)
      result = ReviewSupport.find_duplicate_submissions([ a, b ])
      assert_equal [ b ], result["recA"]
      assert_equal [ a ], result["recB"]
    end

    test "outside window not flagged" do
      a, b = pair(valid_payee, valid_payee, gap_days: 31)
      assert_empty ReviewSupport.find_duplicate_submissions([ a, b ])
    end

    test "different amount not flagged" do
      a, b = pair(valid_payee, valid_payee, amount_b: "61.00")
      assert_empty ReviewSupport.find_duplicate_submissions([ a, b ])
    end

    test "different payee not flagged" do
      a, b = pair(valid_payee, payee_without_bank)
      assert_empty ReviewSupport.find_duplicate_submissions([ a, b ])
    end

    test "missing payee record id never matched" do
      missing = Person.new(record_id: "", name: "(missing payee)", email: "")
      a = dup_expense("recA", missing, amount: "60.00", auto_number: 1, submitted_at: NOW)
      b = dup_expense("recB", missing, amount: "60.00", auto_number: 2, submitted_at: NOW)
      assert_empty ReviewSupport.find_duplicate_submissions([ a, b ])
    end

    test "missing submitted_at still flags (over-warn)" do
      a = dup_expense("recA", valid_payee, amount: "60.00", auto_number: 1, submitted_at: nil)
      b = dup_expense("recB", valid_payee, amount: "60.00", auto_number: 2, submitted_at: nil)
      result = ReviewSupport.find_duplicate_submissions([ a, b ])
      assert_equal [ b ], result["recA"]
      assert_equal [ a ], result["recB"]
    end

    test "three-way duplicate lists both partners" do
      a = dup_expense("recA", valid_payee, amount: "60.00", auto_number: 1, submitted_at: NOW)
      b = dup_expense("recB", valid_payee, amount: "60.00", auto_number: 2, submitted_at: NOW)
      c = dup_expense("recC", valid_payee, amount: "60.00", auto_number: 3, submitted_at: NOW)
      result = ReviewSupport.find_duplicate_submissions([ a, b, c ])
      assert_equal [ b, c ], result["recA"]
      assert_equal [ a, c ], result["recB"]
      assert_equal [ a, b ], result["recC"]
    end

    test "single expense yields no duplicates" do
      a = dup_expense("recA", valid_payee, amount: "60.00", auto_number: 1, submitted_at: NOW)
      assert_empty ReviewSupport.find_duplicate_submissions([ a ])
    end

    # --- attention_summary: blocking vs advisory --------------------------

    test "attention_summary puts approval-blocking reasons in :blocking, the rest in :advisory" do
      # No budget + no bank details -> both hard-block approve_expense.
      # No receipt + over budget -> advisory (approval still proceeds).
      exp = expense(payee: payee_without_bank, budget: nil, amount_excl_vat: BigDecimal("600.00"),
                    receipts: [])
      summary = ReviewSupport.attention_summary(exp, { "recBudget1" => budget }, valid_checker)

      assert_includes summary[:blocking], "no budget"
      assert_includes summary[:blocking], "no bank details"
      assert_includes summary[:advisory], "no receipt"
      # over budget can't be evaluated with a nil budget, so just assert the
      # split keeps advisory-only reasons out of :blocking.
      assert_not_includes summary[:blocking], "no receipt"
    end

    test "an INVALID modulus is advisory, not blocking (approve only checks bank-detail presence)" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [ receipt ])
      summary = ReviewSupport.attention_summary(exp, { "recBudget1" => budget },
                                                FakeChecker.new(ModulusCheck::INVALID))

      assert_includes summary[:advisory], "failed the bank modulus check"
      assert_empty summary[:blocking]
    end

    test "attention_actionable? is false once an expense is Submitted, Paid or Rejected" do
      assert ReviewSupport.attention_actionable?(expense(payee: valid_payee, budget: budget))
      %w[Submitted Paid Rejected].each do |done|
        exp = expense(payee: valid_payee, budget: budget)
        exp.instance_variable_set(:@status, done)
        assert_not ReviewSupport.attention_actionable?(exp), "#{done} is not actionable"
      end
    end
  end
end
