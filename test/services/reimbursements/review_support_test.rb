require "test_helper"
require "bigdecimal"

module Reimbursements
  class ReviewSupportTest < ActiveSupport::TestCase
    # Unpersisted models with record_id, remaining and receipts pinned per instance.
    Person = Reimbursements::Person
    Budget = Reimbursements::Budget
    Expense = Reimbursements::Expense

    # Records each (sort, account) it checks and returns a preset result.
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

    # With the invoice's EUR figure and the GBP one finance types at review.
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

    test "each data problem is named as a reason" do
      [
        [ { amount: BigDecimal("0") }, "no amount" ],
        [ { amount_excl_vat: nil }, "no ex-VAT amount" ],
        [ { amount_excl_vat: BigDecimal("0") }, "no ex-VAT amount" ],
        [ { receipts: [] }, "no receipt" ],
        [ { budget: nil }, "no budget" ],
        [ { payee: payee_without_bank }, "no bank details" ],
        # Gross tracks ex-VAT, or the ex-VAT-over-gross flag trips instead.
        [ { amount: BigDecimal("600.00"), amount_excl_vat: BigDecimal("600.00") }, "over budget" ]
      ].each do |attrs, reason|
        exp = expense(**{ payee: valid_payee, budget: budget, receipts: [ receipt ] }.merge(attrs))
        assert_includes ReviewSupport.needs_attention_reasons(exp, { "recBudget1" => budget }, valid_checker),
                        reason, attrs.inspect
      end
    end

    test "no reason at the budget's limit, without a remaining figure, for OUTSIDE_SPEC or an offloaded receipt" do
      no_remaining = budget(remaining: nil, record_id: "recBudget2")
      large = { amount: BigDecimal("9999.00"), amount_excl_vat: BigDecimal("9999.00") }
      [
        [ { amount: BigDecimal("500.00"), amount_excl_vat: BigDecimal("500.00") }, { "recBudget1" => budget }, valid_checker ],
        [ large.merge(budget: no_remaining), { "recBudget2" => no_remaining }, valid_checker ],
        [ large, {}, valid_checker ],
        [ {}, { "recBudget1" => budget }, FakeChecker.new(ModulusCheck::OUTSIDE_SPEC) ],
        [ { receipts: [], sharepoint_receipt_urls: [ "https://sp/receipt.pdf" ] }, { "recBudget1" => budget }, valid_checker ]
      ].each do |attrs, budgets, checker|
        exp = expense(**{ payee: valid_payee, budget: budget, receipts: [ receipt ] }.merge(attrs))
        assert_empty ReviewSupport.needs_attention_reasons(exp, budgets, checker), attrs.inspect
      end
    end

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

    test "modulus runs on the override account, not the empty linked payee" do
      exp = expense(payee: payee_without_bank, budget: budget, receipts: [ receipt ],
        payee_name_override: "Carol Supplier", sort_code_override: "12-34-56",
        account_number_override: "12345678")
      checker = valid_checker
      assert_not ReviewSupport.needs_attention(exp, { "recBudget1" => budget }, checker)
      assert_equal [ [ "12-34-56", "12345678" ] ], checker.calls
    end

    test "an invalid override account is named a modulus failure" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [ receipt ],
        sort_code_override: "12-34-56", account_number_override: "00000000")
      checker = FakeChecker.new(ModulusCheck::INVALID)
      assert_includes ReviewSupport.needs_attention_reasons(exp, { "recBudget1" => budget }, checker),
                      "failed the bank modulus check"
      assert_equal [ [ "12-34-56", "00000000" ] ], checker.calls
    end

    test "a clean expense has no attention reasons" do
      exp = expense(payee: valid_payee, budget: budget, receipts: [ receipt ])
      assert_empty ReviewSupport.needs_attention_reasons(exp, { "recBudget1" => budget }, valid_checker)
    end

    # On a blank pair the checker returns INVALID, which drew "likely a typo" under "no bank details".
    test "reasons name missing bank details and skip the modulus check" do
      exp = expense(payee: payee_without_bank, budget: budget, receipts: [ receipt ])
      checker = valid_checker
      reasons = ReviewSupport.needs_attention_reasons(exp, { "recBudget1" => budget }, checker)
      assert_includes reasons, "no bank details"
      assert_not_includes reasons, "failed the bank modulus check"
      assert_empty checker.calls
    end

    test "needs_attention is true exactly when there are reasons" do
      clean = expense(payee: valid_payee, budget: budget, receipts: [ receipt ])
      assert_not ReviewSupport.needs_attention(clean, { "recBudget1" => budget }, valid_checker)
      dirty = expense(payee: valid_payee, budget: budget, receipts: [])
      assert ReviewSupport.needs_attention(dirty, { "recBudget1" => budget }, valid_checker)
    end

    # A double space wastes one of EUSA's 18 reference characters. Area-qualified
    # names must stay distinct: payments are reconciled by reference.
    test "auto_payment_reference keeps 18 BACS-safe characters" do
      {
        "Production" => "Production",
        "A very long budget name that exceeds limit" => "A very long budget",
        "Show & Tell" => "Show Tell",
        "Cogito: Marketing" => "Cogito Marketing",
        "Budget: 100 production costs!" => "Budget 100 product",
        "Tech-Theatre" => "Tech-Theatre",
        "  Production  " => "Production",
        "@ Production" => "Production",
        "!A very long name that exceeds" => "A very long name t",
        "" => "",
        "@#$%^&*()" => "",
        "Exactly18CharsLong" => "Exactly18CharsLong",
        "Budget 2026" => "Budget 2026",
        "£100 Budget" => "100 Budget"
      }.each do |input, expected|
        assert_equal expected, ReviewSupport.auto_payment_reference(input), input.inspect
      end
    end

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

    test "a gap past the window, another amount or payee, or a lone claim is no duplicate" do
      [
        pair(valid_payee, valid_payee, gap_days: 31),
        pair(valid_payee, valid_payee, amount_b: "61.00"),
        pair(valid_payee, payee_without_bank),
        [ pair(valid_payee, valid_payee).first ]
      ].each_with_index { |set, i| assert_empty ReviewSupport.find_duplicate_submissions(set), "case #{i}" }
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

    test "attention_summary puts approval-blocking reasons in :blocking, the rest in :advisory" do
      exp = expense(payee: payee_without_bank, budget: nil, amount_excl_vat: nil, receipts: [])
      summary = ReviewSupport.attention_summary(exp, { "recBudget1" => budget }, valid_checker)

      assert_includes summary[:blocking], "no ex-VAT amount"
      assert_includes summary[:blocking], "no budget"
      assert_includes summary[:blocking], "no bank details"
      assert_includes summary[:advisory], "no receipt"
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

    test "a complete international claim has no attention reasons" do
      exp = international_expense
      assert_empty ReviewSupport.needs_attention_reasons(exp, { "recBudget1" => budget }, valid_checker)
    end

    test "the modulus check never runs on an international claim" do
      checker = FakeChecker.new(ModulusCheck::INVALID)
      reasons = ReviewSupport.needs_attention_reasons(international_expense, { "recBudget1" => budget }, checker)

      assert_empty checker.calls
      assert_not_includes reasons, "failed the bank modulus check"
    end

    test "an international claim is blocked without an IBAN or a foreign amount" do
      blank_iban = Person.new(name: "Ausland GmbH", email: "konto@example.de")
      blank_iban.build_payment_details(iban: "", bic: "")
      blank_iban.define_singleton_method(:record_id) { "recPerson3" }
      [
        [ { payee: blank_iban }, "no bank details" ],
        [ { payee: valid_payee }, "no bank details" ], # a UK sort code does not satisfy it
        [ { foreign_amount: nil }, "no EUR amount" ],
        [ { foreign_amount: BigDecimal("0") }, "no EUR amount" ],
        [ { foreign_amount: nil, foreign_currency: "USD" }, "no USD amount" ]
      ].each do |attrs, reason|
        summary = ReviewSupport.attention_summary(international_expense(**attrs),
                                                  { "recBudget1" => budget }, valid_checker)
        assert_includes summary[:blocking], reason, attrs.inspect
      end
    end

    # Ex-VAT mirrors the gross, so a blank GBP amount must not also say "no ex-VAT amount".
    test "a blank international GBP amount blocks, reported once" do
      summary = ReviewSupport.attention_summary(international_expense(amount: nil),
                                                { "recBudget1" => budget }, valid_checker)

      assert_includes summary[:blocking], "no GBP amount"
      assert_not_includes summary[:blocking], "no ex-VAT amount"
      assert_not_includes summary[:advisory], "no GBP amount"
    end

    test "a missing gross amount stays ADVISORY on the UK rail" do
      summary = ReviewSupport.attention_summary(
        expense(payee: valid_payee, budget: budget, receipts: [ receipt ], amount: nil),
        { "recBudget1" => budget }, valid_checker
      )

      assert_includes summary[:advisory], "no amount"
      assert_empty summary[:blocking]
    end
  end
end
