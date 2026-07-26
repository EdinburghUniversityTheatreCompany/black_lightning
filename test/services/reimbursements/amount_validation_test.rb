require "test_helper"

module Reimbursements
  class AmountValidationTest < ActiveSupport::TestCase
    def error(amount:, amount_excl_vat: "")
      AmountValidation.error_for(amount: amount, amount_excl_vat: amount_excl_vat)
    end

    test "a positive amount with a blank excl VAT is valid" do
      assert_nil error(amount: "20.00", amount_excl_vat: "")
    end

    test "a positive amount with a positive excl VAT is valid" do
      assert_nil error(amount: "20.00", amount_excl_vat: "16.67")
    end

    test "zero excl VAT is the leave-alone sentinel, not an error" do
      assert_nil error(amount: "20.00", amount_excl_vat: "0")
    end

    test "a blank amount is rejected" do
      assert_match(/valid amount/i, error(amount: ""))
    end

    test "a non-positive amount is rejected" do
      assert_match(/valid amount/i, error(amount: "0"))
      assert_match(/valid amount/i, error(amount: "-5"))
    end

    test "a non-numeric amount is rejected" do
      assert_match(/valid amount/i, error(amount: "abc"))
    end

    test "a negative excl VAT is rejected" do
      assert_match(/excl. VAT/i, error(amount: "20.00", amount_excl_vat: "-1"))
    end

    test "a non-numeric excl VAT is rejected" do
      assert_match(/excl. VAT/i, error(amount: "20.00", amount_excl_vat: "abc"))
    end

    test "an excl VAT greater than the total amount is rejected" do
      assert_match(/can't be more than the total/i, error(amount: "20.00", amount_excl_vat: "25.00"))
    end

    test "an excl VAT equal to the total amount is valid" do
      assert_nil error(amount: "20.00", amount_excl_vat: "20.00")
    end

    # Reading is AmountParser's job now, so the finance forms accept the money
    # formats the submitter form and the budget forms have always accepted. They
    # used to reject these, which meant "what counts as an amount" had two answers
    # depending on which form you were standing in front of.
    test "a currency symbol and thousands separators are accepted" do
      assert_nil error(amount: "£1,200")
      assert_nil error(amount: "£1,200.50", amount_excl_vat: "£1,000")
    end

    test "a comma decimal is accepted, and read as a decimal not a thousands separator" do
      assert_nil error(amount: "12,50")
      assert_equal BigDecimal("12.50"), AmountValidation.amount("12,50")
    end

    # The reason this module used to do its own stricter reading was that the write
    # path re-read the RAW string with to_f, so the two parsers could disagree.
    # These accessors close that off: the caller writes the very value that was
    # validated. AR casts a string to a decimal column with to_d, which reads
    # "£1,200" as 0 — a validated amount silently becoming a zero payment.
    test "the value to write is the parsed BigDecimal that was validated" do
      assert_equal BigDecimal("1200"), AmountValidation.amount("£1,200")
      assert_equal BigDecimal("20.5"), AmountValidation.amount("20.50")
      assert_equal 0, "£1,200".to_d, "premise: handing the raw string to AR would store zero"
    end

    test "amount_excl_vat answers nil for the leave-alone sentinels" do
      assert_nil AmountValidation.amount_excl_vat("")
      assert_nil AmountValidation.amount_excl_vat("0")
      assert_nil AmountValidation.amount_excl_vat("abc")
      assert_equal BigDecimal("16.67"), AmountValidation.amount_excl_vat("16.67")
    end

    # Kernel#Float accepts "0x1A" as hex (26.0) and "1e10" as scientific notation.
    # BigDecimal rejects the hex outright, and the sanity ceiling catches the
    # scientific notation, so neither can reach a payment.
    test "a hex-looking amount is rejected, not silently accepted as if parsed by Float()" do
      assert_match(/valid amount/i, error(amount: "0x1A"))
    end

    test "a hex-looking excl VAT is rejected the same way" do
      assert_match(/excl. VAT/i, error(amount: "20.00", amount_excl_vat: "0x1A"))
    end

    test "scientific notation is rejected, not silently truncated by to_f" do
      assert_match(/valid amount/i, error(amount: "1e10"))
    end

    test "an amount far beyond any real claim is rejected as a fat-finger typo" do
      assert_match(/valid amount/i, error(amount: "999999999.00"))
    end

    test "an amount right at the ceiling is accepted" do
      assert_nil error(amount: AmountValidation::MAX_AMOUNT.to_s)
    end

    test "an excl VAT far beyond any real claim is rejected the same way" do
      assert_match(/excl. VAT/i, error(amount: "20.00", amount_excl_vat: "999999999.00"))
    end
  end
end
