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
        assert_equal "https://airtable/thumb-large", expense.receipts.first.thumbnail_url
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

      # --- operator field reads ------------------------------------------

      test "maps budget remaining and initial budget" do
        f = FIELD_IDS[:budgets]
        record = airtable_budget_record
        record["fields"][f[:initial_budget]] = 1000.0
        record["fields"][f[:remaining]] = 250.5
        budget = mapper.budget(record)
        assert_equal BigDecimal("1000.0"), budget.initial_budget
        assert_equal BigDecimal("250.5"), budget.remaining
      end

      test "maps operator expense fields" do
        f = FIELD_IDS[:expenses]
        record = airtable_expense_record(overrides: {
          f[:nominal_code_override] => "9999",
          f[:submitted_to_eusa_date] => "2026-05-13",
          f[:payment_confirmed_date] => "2026-05-20",
          f[:batch] => [ "recBat1" ],
          f[:producer_notified] => true,
          f[:receipts_offloaded] => true,
          f[:sharepoint_receipt_urls] => "https://sp/a.pdf\nhttps://sp/b.pdf",
          f[:ai_check_status] => "Pass", f[:ai_comment] => "Looks fine",
          f[:ai_checked_at] => "2026-05-01T09:00:00Z"
        })
        expense = mapper.expense(record, people_by_id: {}, budgets_by_id: {})

        assert_equal "9999", expense.nominal_code_override
        assert_equal Date.new(2026, 5, 13), expense.submitted_to_eusa_date
        assert_equal Date.new(2026, 5, 20), expense.payment_confirmed_date
        assert_equal "recBat1", expense.batch_id
        assert expense.producer_notified
        assert expense.receipts_offloaded
        assert_equal [ "https://sp/a.pdf", "https://sp/b.pdf" ], expense.sharepoint_receipt_urls
        assert_equal "Pass", expense.ai_check_status
        assert_equal "Looks fine", expense.ai_comment
        assert_not_nil expense.ai_checked_at
      end

      test "maps a batch record" do
        batch = mapper.batch(airtable_batch_record(eusa_draft_created: true, sharepoint_backup_url: "https://sp/b"))
        assert_equal "recBat1", batch.record_id
        assert_equal "BACS 2026-05-13", batch.name
        assert_equal Date.new(2026, 5, 13), batch.date_sent
        assert batch.eusa_draft_created
        assert_equal "https://sp/b", batch.sharepoint_backup_url
      end

      test "maps a eusa actual record and its dedup key" do
        actual = mapper.eusa_actual(airtable_eusa_actual_record(linked_expense: [ "recExp1" ]))
        assert_equal "439999", actual.nominal_code
        assert_equal "F40", actual.cost_centre
        assert_equal BigDecimal("123.45"), actual.debit
        assert_equal [ "recExp1" ], actual.linked_expense_ids
        assert_equal Date.new(2026, 5, 13), actual.date
        assert_equal Reconciliation.actuals_row_dedup_key("439999", "Alice Producer", BigDecimal("123.45"), nil),
          actual.dedup_key
      end

      # --- operator write transforms -------------------------------------

      test "expense field payload transforms operator write fields" do
        f = FIELD_IDS[:expenses]
        payload = mapper.expense_fields(
          status: "Submitted", batch_id: "recBat9",
          submitted_to_eusa_date: Date.new(2026, 5, 13),
          sharepoint_receipt_urls: [ "https://sp/a.pdf", "https://sp/b.pdf" ],
          ai_checked_at: Time.utc(2026, 5, 1, 9, 0, 0)
        )
        assert_equal "Submitted", payload[f[:status]]
        assert_equal [ "recBat9" ], payload[f[:batch]]
        assert_equal "2026-05-13", payload[f[:submitted_to_eusa_date]]
        assert_equal "https://sp/a.pdf\nhttps://sp/b.pdf", payload[f[:sharepoint_receipt_urls]]
        assert_equal "2026-05-01T09:00:00Z", payload[f[:ai_checked_at]]
      end

      test "builds a batch field payload keyed by field id with an iso date" do
        f = FIELD_IDS[:batches]
        payload = mapper.batch_fields(date_sent: Date.new(2026, 5, 13), notes: "SP: url",
                                      eusa_draft_created: true, sharepoint_backup_url: "https://sp/x",
                                      producer_notifications_sent: nil)
        assert_equal "2026-05-13", payload[f[:date_sent]]
        assert_equal "SP: url", payload[f[:notes]]
        assert payload[f[:eusa_draft_created]]
        assert_equal "https://sp/x", payload[f[:sharepoint_backup_url]]
        assert_not payload.key?(f[:producer_notifications_sent]), "nil values are dropped"
      end
    end
  end
end
