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
        receipts: [ upload ], vat_itemised: "true"
      }
      ExpenseForm.new(defaults.merge(attrs))
    end

    test "valid with the full set of required fields" do
      form = build_form
      assert form.valid?, form.errors.full_messages.to_sentence
      assert_equal BigDecimal("12.50"), form.amount_decimal
    end

    test "parses currency-formatted amounts" do
      form = build_form(amount: "£1,234.56", amount_excl_vat: "£1,028.80")
      assert form.valid?, form.errors.full_messages.to_sentence
      assert_equal BigDecimal("1234.56"), form.amount_decimal
    end

    test "requires all the airtable form's required fields" do
      form = ExpenseForm.new
      assert_not form.valid?
      %i[amount amount_excl_vat budget_record_id description payment_reference receipts].each do |field|
        assert form.errors[field].present?, "expected error on #{field}"
      end
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

    test "vat soft block requires acknowledgement when receipt lacks vat" do
      form = build_form(vat_itemised: "false", amount_excl_vat: "12.50")
      assert_not form.valid?
      assert form.errors[:vat_acknowledged].present?

      acknowledged = build_form(vat_itemised: "false", amount_excl_vat: "12.50", vat_acknowledged: "1")
      assert acknowledged.valid?, acknowledged.errors.full_messages.to_sentence
    end

    test "vat soft block also triggers when excl equals total" do
      form = build_form(vat_itemised: "unknown", amount_excl_vat: "12.50")
      assert_not form.valid?
      assert form.errors[:vat_acknowledged].present?
    end

    test "no vat block when vat is itemised and excl is below total" do
      assert build_form.valid?
    end

    test "receipts optional only when require_receipts is off (edit)" do
      form = build_form(receipts: [], require_receipts: false)
      assert form.valid?, form.errors.full_messages.to_sentence
    end

    test "rejects disallowed receipt types" do
      bad = Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/reimbursements_receipt.pdf"), "application/zip"
      )
      assert_not build_form(receipts: [ bad ]).valid?
    end

    test "validates override formats only when present" do
      assert build_form(payee_name_override: "Stage Supplies Ltd").valid?
      assert_not build_form(sort_code_override: "80-2").valid?
      assert_not build_form(account_number_override: "123").valid?
      assert build_form(sort_code_override: "80-22-60", account_number_override: "12345678").valid?
    end

    test "create_attrs carries person, pending status and normalized values" do
      attrs = build_form.create_attrs("recPer1")
      assert_equal "recPer1", attrs[:person_record_id]
      assert_equal Status::PENDING, attrs[:status]
      assert_equal BigDecimal("12.50"), attrs[:amount]
      assert_nil attrs[:payee_name_override]
    end
  end
end
