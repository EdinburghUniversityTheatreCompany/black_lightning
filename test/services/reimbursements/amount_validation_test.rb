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

    # Kernel#Float alone accepts "0x1A" as hex (26.0) and "1e10" as scientific
    # notation, but String#to_f — used by the actual write path,
    # Mapper#expense_fields — parses either as 0.0/1.0, silently disagreeing
    # with whatever this validator just approved. Rejecting anything that
    # isn't a plain decimal number closes that gap at the source rather than
    # trying to keep two separate parsers in sync.
    test "a hex-looking amount is rejected, not silently accepted as if parsed by Float()" do
      assert_match(/valid amount/i, error(amount: "0x1A"))
    end

    test "a hex-looking excl VAT is rejected the same way" do
      assert_match(/excl. VAT/i, error(amount: "20.00", amount_excl_vat: "0x1A"))
    end

    test "scientific notation is rejected, not silently truncated by to_f" do
      assert_match(/valid amount/i, error(amount: "1e10"))
    end
  end
end
