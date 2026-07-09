require "test_helper"

module Reimbursements
  module Airtable
    class MapperTest < ActiveSupport::TestCase
      include ReimbursementsTestHelpers

      def mapper
        @mapper ||= Mapper.new(reimbursements_test_config)
      end

      test "maps a person record" do
        person = mapper.person(airtable_person_record(sort_code: "112233", account_number: "12345678", verified: true))
        assert_equal "recPer1", person.record_id
        assert_equal "Pat Producer", person.name
        assert_equal "pat@example.com", person.email
        assert person.verified
        assert person.bank_details?
      end

      test "maps a budget record" do
        budget = mapper.budget(airtable_budget_record)
        assert_equal "Props", budget.name
        assert_equal "4000", budget.nominal_code
        assert budget.active
      end

      test "maps an expense record joining people and budgets" do
        person = mapper.person(airtable_person_record)
        budget = mapper.budget(airtable_budget_record)
        expense = mapper.expense(airtable_expense_record,
                                 people_by_id: { "recPer1" => person },
                                 budgets_by_id: { "recBud1" => budget })

        assert_equal "recExp1", expense.record_id
        assert_equal person, expense.person
        assert_equal budget, expense.budget
        assert_equal BigDecimal("12.5"), expense.amount
        assert_equal BigDecimal("10.42"), expense.amount_excl_vat
        assert_equal "Pending", expense.status
        assert_equal 1, expense.receipts.size
        assert_equal "receipt.pdf", expense.receipts.first.filename
      end

      test "tolerates missing budget, payee and amounts" do
        record = airtable_expense_record
        record["fields"].delete(FIELD_IDS[:expenses][:budget])
        record["fields"].delete(FIELD_IDS[:expenses][:payee])
        record["fields"].delete(FIELD_IDS[:expenses][:amount])

        expense = mapper.expense(record, people_by_id: {}, budgets_by_id: {})
        assert_nil expense.budget
        assert_nil expense.person
        assert_nil expense.amount
        assert expense.needs_completion?
      end

      test "builds an expense field payload keyed by field id" do
        payload = mapper.expense_fields(
          person_record_id: "recPer9", budget_record_id: "recBud9",
          amount: BigDecimal("20.00"), amount_excl_vat: nil,
          description: "Gaffer tape", payment_reference: "TAPE PAT",
          status: "Pending", expense_type: "Invoice"
        )

        f = FIELD_IDS[:expenses]
        assert_equal [ "recPer9" ], payload[f[:payee]]
        assert_equal [ "recBud9" ], payload[f[:budget]]
        assert_in_delta 20.0, payload[f[:amount]]
        assert_equal "Gaffer tape", payload[f[:description]]
        assert_equal "Pending", payload[f[:status]]
        assert_equal "Invoice", payload[f[:type]]
        assert_not payload.key?(f[:amount_excl_vat]), "nil attrs must be omitted"
      end

      test "builds a person field payload" do
        payload = mapper.person_fields(name: "Pat", email: "pat@example.com", sort_code: "112233")
        f = FIELD_IDS[:people]
        assert_equal({ f[:name] => "Pat", f[:email] => "pat@example.com", f[:sort_code] => "112233" }, payload)
      end
    end
  end
end
