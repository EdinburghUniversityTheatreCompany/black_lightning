require "test_helper"

module Reimbursements
  class ExpenseTest < ActiveSupport::TestCase
    def build_expense(**overrides)
      defaults = {
        record_id: "recExp1",
        auto_number: 7,
        person: Person.new(record_id: "recPer1", name: "Pat Producer", email: "pat@example.com"),
        amount: BigDecimal("12.50"),
        amount_excl_vat: BigDecimal("10.42"),
        budget: Budget.new(record_id: "recBud1", name: "Props", nominal_code: "4000"),
        description: "Fake blood, 2 litres",
        receipts: [ Attachment.new(attachment_id: "att1", filename: "receipt.pdf", url: "https://x", size_bytes: 100) ],
        status: Status::PENDING,
        payment_reference: "PROPS PAT"
      }
      Expense.new(**defaults.merge(overrides))
    end

    test "editable only while pending" do
      assert build_expense.editable?
      assert_not build_expense(status: Status::APPROVED).editable?
      assert_not build_expense(status: Status::REJECTED).editable?
    end

    test "complete expense does not need completion" do
      assert_not build_expense.needs_completion?
    end

    test "needs completion when required fields are missing" do
      assert build_expense(budget: nil).needs_completion?
      assert build_expense(payment_reference: "").needs_completion?
      assert build_expense(amount_excl_vat: nil).needs_completion?
      assert build_expense(receipts: []).needs_completion?
      assert build_expense(description: "").needs_completion?
    end

    test "payee override detection" do
      assert_not build_expense.payee_override?
      assert build_expense(payee_name_override: "Stage Supplies Ltd").payee_override?
      assert build_expense(sort_code_override: "112233").payee_override?
    end

    test "status badge variants cover all statuses" do
      Status.all.each do |status|
        assert_kind_of Symbol, Status.badge_variant(status)
      end
    end

    test "person may be nil" do
      assert_nil build_expense(person: nil).person
    end
  end
end
