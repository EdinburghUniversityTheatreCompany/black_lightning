require "test_helper"

module Reimbursements
  class PaymentDetailsFormTest < ActiveSupport::TestCase
    def build_form(**attrs)
      PaymentDetailsForm.new({ name: "Pat Producer", sort_code: "80-22-60", account_number: "12345678" }.merge(attrs))
    end

    test "valid with dashed sort code, normalizes for storage" do
      form = build_form
      assert form.valid?
      assert_equal "802260", form.normalized_sort_code
      assert_equal "12345678", form.normalized_account_number
    end

    test "requires all fields" do
      form = PaymentDetailsForm.new
      assert_not form.valid?
      assert form.errors[:name].present?
      assert form.errors[:sort_code].present?
      assert form.errors[:account_number].present?
    end

    test "rejects malformed sort codes and account numbers" do
      assert_not build_form(sort_code: "80-22").valid?
      assert_not build_form(sort_code: "abcdef").valid?
      assert_not build_form(account_number: "1234").valid?
      assert_not build_form(account_number: "123456789").valid?
    end
  end
end
