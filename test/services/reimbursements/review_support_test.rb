require "test_helper"
require "bigdecimal"

module Reimbursements
  class ReviewSupportTest < ActiveSupport::TestCase
    # These exercise the pure ReviewSupport predicates. The AR models keep the
    # POROs' public interface, so they serve as value objects built unpersisted:
    # the computed record_id/remaining/receipts (derived from the DB in
    # production) are pinned per-instance to isolate the logic under test.
    Person = Reimbursements::Person
    Budget = Reimbursements::Budget
    Expense = Reimbursements::Expense

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

    def build_person(record_id:, name:, email:, sort_code: "", account_number: "")
      person = Person.new(name: name, email: email)
      person.build_payment_details(sort_code: sort_code, account_number: account_number)
      person.define_singleton_method(:record_id) { record_id }
      person
    end

    def valid_payee
      build_person(record_id: "recPerson1", name: "Alice Producer", email: "alice@example.com",
        sort_code: "12-34-56", account_number: "12345678")
    end

    def payee_without_bank
      build_person(record_id: "recPerson2", name: "Bob NoBank", email: "bob@example.com",
        sort_code: "", account_number: "")
    end

    def international_payee
      person = Person.new(name: "Ausland GmbH", email: "konto@example.de")
      person.build_payment_details(iban: "DE89370400440532013000", bic: "DEUTDEFF500")
      person.define_singleton_method(:record_id) { "recPerson3" }
      person
    end

    # An international claim as it looks once finance has done its part: the EUR
    # figure from the invoice and the GBP equivalent they typed at review.
    def international_expense(payee: nil, **extra)
      expense(payee: payee || international_payee, budget: budget, receipts: [ receipt ],
        payment_method: Expense::PAYMENT_METHOD_INTERNATIONAL,
        foreign_amount: BigDecimal("266.69"), foreign_currency: Expense::CURRENCY_EUR,
        **extra)
    end

    def budget(remaining: BigDecimal("500.00"), nominal_code: "439999", record_id: "recBudget1")
      remaining_value = remaining
      rid = record_id
      b = Budget.new(name: "Production", nominal_code: nominal_code)
      b.define_singleton_method(:remaining) { remaining_value }
      b.define_singleton_method(:record_id) { rid }
      b
    end

    def receipt
      Attachment.new(attachment_id: "att1", filename: "receipt.pdf",
        url: "https://example.com/receipt.pdf", size_bytes: 1024)
    end

    def expense(payee:, budget:, amount_excl_vat: BigDecimal("50.00"), receipts: [], **extra)
      sharepoint = extra.delete(:sharepoint_receipt_urls)
      exp = Expense.new(auto_number: 1, status: Status::PENDING,
        person: payee, amount: BigDecimal("60.00"), amount_excl_vat: amount_excl_vat,
        budget: budget, description: "Test expense", **extra)
      exp.sharepoint_receipt_urls = Array(sharepoint).join("\n") if sharepoint
      exp.instance_variable_set(:@receipts, receipts)
      exp.define_singleton_method(:record_id) { "recExpense1" }
      exp
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
      placeholder = budget(record_id: "", nominal_code: "")
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

    # Was "Show  Tell": the gsub leaves a space either side of what it dropped,
    # and #auto_payment_reference now collapses that run — a double space wastes
    # one of the 18 characters EUSA reads.
    test "special chars stripped before truncation, and the gap they leave collapsed" do
      assert_equal "Show Tell", ReviewSupport.auto_payment_reference("Show & Tell")
    end

    # It is fed Budget#display_name, whose em dash is not BACS-safe: three
    # shows' "Marketing" lines otherwise derive one identical reference, and
    # the reference is what a payment is reconciled back to a claim by.
    test "an area-qualified budget name reads as the show and the line" do
      assert_equal "Cogito Marketing", ReviewSupport.auto_payment_reference("Cogito — Marketing")
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
      exp = Expense.new(auto_number: auto_number, status: Status::PENDING,
        person: payee, amount: BigDecimal(amount), amount_excl_vat: BigDecimal(amount),
        budget: budget, description: "Test expense", submitted_at: submitted_at)
      exp.instance_variable_set(:@receipts, [])
      rid = record_id
      exp.define_singleton_method(:record_id) { rid }
      exp
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
      missing = build_person(record_id: "", name: "(missing payee)", email: "")
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
        exp.status = done
        assert_not ReviewSupport.attention_actionable?(exp), "#{done} is not actionable"
      end
    end

    # --- needs_attention: the international rail ----------------------------
    #
    # These are the rules that decide whether an international claim can ever
    # leave the review queue. Before payment_method existed the UK sort-code
    # pair was read for every claim, so an IBAN-only one was permanently stuck.

    test "a complete international claim has no attention reasons" do
      exp = international_expense
      assert_empty ReviewSupport.needs_attention_reasons(exp, { "recBudget1" => budget }, valid_checker)
    end

    test "the modulus check never runs on an international claim" do
      # It is a UK sort-code/account-number algorithm; running it on a payee
      # with no sort code would fail every international claim on a check that
      # does not apply to it.
      checker = FakeChecker.new(ModulusCheck::INVALID)
      reasons = ReviewSupport.needs_attention_reasons(international_expense, { "recBudget1" => budget }, checker)

      assert_empty checker.calls
      assert_not_includes reasons, "failed the bank modulus check"
    end

    test "an international claim with no IBAN is blocked" do
      payee = Person.new(name: "Ausland GmbH", email: "konto@example.de")
      payee.build_payment_details(iban: "", bic: "")
      payee.define_singleton_method(:record_id) { "recPerson3" }
      summary = ReviewSupport.attention_summary(international_expense(payee: payee),
                                                { "recBudget1" => budget }, valid_checker)

      assert_includes summary[:blocking], "no bank details"
    end

    test "a UK sort code does not satisfy an international claim" do
      # The whole reason the predicate had to become rail-aware.
      summary = ReviewSupport.attention_summary(international_expense(payee: valid_payee),
                                                { "recBudget1" => budget }, valid_checker)

      assert_includes summary[:blocking], "no bank details"
    end

    test "an international claim with no EUR amount is blocked" do
      # foreign_amount is what goes on EUSA's form. Without it there is nothing
      # to send, and the GBP figure beside it cannot stand in — EUSA's bank
      # pays the supplier in their own currency.
      summary = ReviewSupport.attention_summary(international_expense(foreign_amount: nil),
                                                { "recBudget1" => budget }, valid_checker)

      assert_includes summary[:blocking], "no EUR amount"
    end

    test "a zero EUR amount is blocked too" do
      summary = ReviewSupport.attention_summary(international_expense(foreign_amount: BigDecimal("0")),
                                                { "recBudget1" => budget }, valid_checker)

      assert_includes summary[:blocking], "no EUR amount"
    end

    test "an international claim with no GBP amount is BLOCKED, not merely flagged" do
      # This is what enforces "finance types the GBP figure at review": the
      # budget rollups are all GBP, so approving without one would book the
      # claim against the budget at nothing.
      summary = ReviewSupport.attention_summary(international_expense(amount: nil),
                                                { "recBudget1" => budget }, valid_checker)

      assert_includes summary[:blocking], "no GBP amount"
      assert_not_includes summary[:advisory], "no GBP amount"
    end

    # Its ex-VAT amount mirrors its gross, so a blank GBP amount trips both
    # rules — and "no ex-VAT amount" would send finance looking for a field this
    # rail does not have.
    test "a blank international amount is reported once, as the GBP amount" do
      summary = ReviewSupport.attention_summary(international_expense(amount: nil),
                                                { "recBudget1" => budget }, valid_checker)

      assert_includes summary[:blocking], "no GBP amount"
      assert_not_includes summary[:blocking], "no ex-VAT amount"
    end

    test "a missing gross amount stays ADVISORY on the UK rail" do
      # Only the international rail hard-blocks on it. A UK claim's amount is
      # the submitter's own figure and has always been a soft flag; promoting
      # it would start refusing approvals that work today.
      summary = ReviewSupport.attention_summary(
        expense(payee: valid_payee, budget: budget, receipts: [ receipt ], amount: nil),
        { "recBudget1" => budget }, valid_checker
      )

      assert_includes summary[:advisory], "no amount"
      assert_empty summary[:blocking]
    end

    test "the EUR amount is not read on a UK claim" do
      # A UK claim never has one, and demanding it would block every one of them.
      summary = ReviewSupport.attention_summary(
        expense(payee: valid_payee, budget: budget, receipts: [ receipt ]),
        { "recBudget1" => budget }, valid_checker
      )

      assert_not_includes summary[:blocking], "no EUR amount"
    end
  end
end
