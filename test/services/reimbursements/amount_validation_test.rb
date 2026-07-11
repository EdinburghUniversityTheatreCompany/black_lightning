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
  end
end
