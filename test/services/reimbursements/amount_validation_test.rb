require "test_helper"

module Reimbursements
  class AmountValidationTest < ActiveSupport::TestCase
    def error(amount:, amount_excl_vat: "")
      AmountValidation.error_for(amount: amount, amount_excl_vat: amount_excl_vat)
    end

    # A zero excl VAT is the leave-alone sentinel; the formats are the ones
    # AmountParser reads for every other form.
    test "valid amounts are accepted" do
      [ [ "20.00", "" ], [ "20.00", "16.67" ], [ "20.00", "0" ], [ "20.00", "20.00" ],
        [ "£1,200", "" ], [ "£1,200.50", "£1,000" ], [ "12,50", "" ],
        [ AmountValidation::MAX_AMOUNT.to_s, "" ] ].each do |amount, excl|
        assert_nil error(amount: amount, amount_excl_vat: excl), "#{amount.inspect} / #{excl.inspect}"
      end
    end

    # BigDecimal rejects hex; the ceiling catches scientific notation and typos.
    test "an unusable amount is rejected" do
      [ "", "0", "-5", "abc", "0x1A", "1e10", "999999999.00" ].each do |amount|
        assert_match(/valid amount/i, error(amount: amount), amount.inspect)
      end
    end

    test "an unusable excl VAT is rejected" do
      %w[-1 abc 0x1A 999999999.00].each do |excl|
        assert_match(/excl. VAT/i, error(amount: "20.00", amount_excl_vat: excl), excl)
      end
    end

    test "an excl VAT greater than the total amount is rejected" do
      assert_match(/can't be more than the total/i, error(amount: "20.00", amount_excl_vat: "25.00"))
    end

    # AR casts a string to a decimal column with to_d, which reads "£1,200" as 0.
    test "the value to write is the parsed BigDecimal that was validated" do
      assert_equal BigDecimal("1200"), AmountValidation.amount("£1,200")
      assert_equal BigDecimal("20.5"), AmountValidation.amount("20.50")
      assert_equal BigDecimal("12.50"), AmountValidation.amount("12,50")
      assert_equal 0, "£1,200".to_d, "premise: handing the raw string to AR would store zero"
    end

    test "amount_excl_vat answers nil for the leave-alone sentinels" do
      assert_nil AmountValidation.amount_excl_vat("")
      assert_nil AmountValidation.amount_excl_vat("0")
      assert_nil AmountValidation.amount_excl_vat("abc")
      assert_equal BigDecimal("16.67"), AmountValidation.amount_excl_vat("16.67")
    end
  end
end
