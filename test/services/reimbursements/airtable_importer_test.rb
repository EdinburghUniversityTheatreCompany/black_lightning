require "test_helper"

module Reimbursements
  class AirtableImporterTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    RECEIPT_BYTES = ("x" * 1234).freeze

    def seeded_store
      build_fake_store(
        people: [
          airtable_person_record(id: "recPer1", name: "Pat Producer", email: "pat@example.com",
                                 sort_code: "80-22-60", account_number: "12345678", verified: true),
          airtable_person_record(id: "recPer2", name: "No Bank", email: "nobank@example.com"),
          airtable_person_record(id: "recPer3", name: "No Email", email: "")
        ],
        budgets: [
          airtable_budget_record(id: "recBud1", name: "Props", nominal_code: "4000",
                                 initial_budget: 120.0, owner_ids: [ "recPer1" ], notes: "note"),
          airtable_budget_record(id: "recBud2", name: "Grant", budget_type: "Income")
        ],
        budget_forecasts: [
          airtable_budget_forecast_record(id: "recFc1", budget_id: "recBud1", amount: 150.0,
                                          date: "2026-06-01", reason: "revised")
        ],
        batches: [
          airtable_batch_record(id: "recBat1", name: "BACS legacy", date_sent: "2026-05-13",
                                eusa_draft_created: true),
          airtable_batch_record(id: "recBat2", name: "BACS drafted", date_sent: nil,
                                draft_message_id: "AAMkAG=")
        ],
        expenses: [
          airtable_expense_record(id: "recExp1", payee_id: "recPer1", budget_id: "recBud1",
                                  amount: 12.5, amount_excl_vat: 10.42, status: "Paid",
                                  overrides: {
                                    FIELD_IDS[:expenses][:batch] => [ "recBat1" ],
                                    FIELD_IDS[:expenses][:submitted_at] => "2026-05-01T10:00:00.000Z"
                                  }),
          airtable_expense_record(id: "recExp2", payee_id: "recPer2", budget_id: "recBud1",
                                  auto_number: 2, amount: 24.0, amount_excl_vat: 20.0,
                                  status: "Pending", receipts: [])
        ],
        eusa_actuals: [
          airtable_eusa_actual_record(id: "recAct1", linked_expense: [ "recExp1" ],
                                      linked_budget: [ "recBud1" ], period: "P1")
        ]
      )
    end

    def import!(store:, responses: [ [ 200, RECEIPT_BYTES ] ], label: "Fringe 2026", remap: false)
      transport = FakeHttp.new(responses)
      io = StringIO.new
      AirtableImporter.new(store: store, transport: transport, io: io,
                           financial_year_label: label).import!(remap_native_tables: remap)
      [ transport, io ]
    end

    test "imports every table, streams receipts and stamps the financial year" do
      store, = seeded_store
      import!(store: store)

      year = FinancialYear.find_by!(label: "Fringe 2026")
      assert year.active

      pat = Person.find_by!(airtable_record_id: "recPer1")
      assert_equal "80-22-60", pat.sort_code
      assert pat.verified?
      assert_not Person.find_by!(airtable_record_id: "recPer2").payment_details
      assert_nil Person.find_by!(airtable_record_id: "recPer3").email

      props = Budget.find_by!(airtable_record_id: "recBud1")
      assert_equal [ pat.record_id ], props.owner_ids
      assert_equal "note", props.notes
      assert_equal CostCentre.default, props.cost_centre
      assert_equal year, props.financial_year
      assert_equal BigDecimal("150"), props.current_forecast

      legacy = Batch.find_by!(airtable_record_id: "recBat1")
      assert legacy.eusa_draft_created # via date_sent despite no message id
      assert_equal "AAMkAG=", Batch.find_by!(airtable_record_id: "recBat2").draft_message_id

      expense = Expense.find_by!(airtable_record_id: "recExp1")
      assert_equal pat, expense.person
      assert_equal props, expense.budget
      assert_equal legacy, expense.batch
      assert_equal year, expense.financial_year
      assert_equal BigDecimal("12.5"), expense.amount
      assert_equal "Paid", expense.status
      assert_equal 1, expense.receipt_files.count
      assert_equal "receipt.pdf", expense.receipt_files.sole.filename.to_s
      assert_equal RECEIPT_BYTES.bytesize, expense.receipt_files.sole.byte_size

      actual = EusaActual.find_by!(airtable_record_id: "recAct1")
      assert_equal expense, actual.expense
      assert_equal props, actual.budget
      assert_equal year, actual.financial_year
    end

    test "is idempotent: a re-run changes nothing and skips receipt downloads" do
      store, = seeded_store
      import!(store: store)
      counts = [ Person.count, Budget.count, BudgetForecast.count, Batch.count,
                 Expense.count, EusaActual.count, ActiveStorage::Attachment.count ]

      # No queued responses: a second download attempt would exhaust FakeHttp.
      transport, = import!(store: store, responses: [])
      assert_empty transport.requests
      assert_equal counts, [ Person.count, Budget.count, BudgetForecast.count, Batch.count,
                             Expense.count, EusaActual.count, ActiveStorage::Attachment.count ]
    end

    test "backfills users and remaps endorsements and batch attempts" do
      user = users(:user)
      user.update_columns(airtable_person_id: "recPer1")
      endorsement = OwnerEndorsement.create!(expense_record_id: "recExp1",
                                             budget_record_id: "recBud1",
                                             endorsed_by_person_id: "recPer1",
                                             endorsed_at: Time.current)
      attempt = BatchAttempt.create!(cost_centre: CostCentre.default, status: "completed",
                                     batch_record_id: "recBat1")

      store, = seeded_store
      import!(store: store, remap: true)

      assert_equal Person.find_by!(airtable_record_id: "recPer1").id,
                   user.reload.reimbursements_person_id

      endorsement.reload
      assert_equal Expense.find_by!(airtable_record_id: "recExp1").record_id,
                   endorsement.expense_record_id
      assert_equal Budget.find_by!(airtable_record_id: "recBud1").record_id,
                   endorsement.budget_record_id
      assert_equal Person.find_by!(airtable_record_id: "recPer1").record_id,
                   endorsement.endorsed_by_person_id

      assert_equal Batch.find_by!(airtable_record_id: "recBat1").record_id,
                   attempt.reload.batch_record_id

      # Re-running must leave the already-remapped (numeric) ids alone.
      import!(store: store, responses: [], remap: true)
      assert_equal endorsement.expense_record_id, endorsement.reload.expense_record_id
    end

    test "refuses to import duplicate People emails" do
      store, = build_fake_store(people: [
        airtable_person_record(id: "recPer1", email: "dupe@example.com"),
        airtable_person_record(id: "recPer2", name: "Other", email: "DUPE@example.com")
      ])

      error = assert_raises(AirtableImporter::ImportError) { import!(store: store) }
      assert_match(/dupe@example.com/, error.message)
      assert_equal 0, Person.count
    end

    test "fails loudly when a receipt download fails" do
      store, = seeded_store
      assert_raises(AirtableImporter::ImportError) do
        import!(store: store, responses: [ [ 403, "expired" ] ])
      end
    end

    test "fails loudly on an endorsement pointing at an unimported record" do
      OwnerEndorsement.create!(expense_record_id: "recGhost", budget_record_id: "recBud1",
                               endorsed_by_person_id: "recPer1", endorsed_at: Time.current)
      store, = seeded_store

      error = assert_raises(AirtableImporter::ImportError) { import!(store: store, remap: true) }
      assert_match(/recGhost/, error.message)
    end
    test "a rehearsal import leaves the endorsement gate untouched (no remap)" do
      endorsement = OwnerEndorsement.create!(expense_record_id: "recExp1",
                                             budget_record_id: "recBud1",
                                             endorsed_by_person_id: "recPer1",
                                             endorsed_at: Time.current)
      store, = seeded_store

      import!(store: store) # rehearsal default: remap_native_tables false

      assert_equal "recExp1", endorsement.reload.expense_record_id,
                   "the live Airtable backend must keep matching these ids until the flip"
      assert_equal "recPer1", endorsement.endorsed_by_person_id
    end

    test "unremap! restores the Airtable ids for a rollback flip" do
      endorsement = OwnerEndorsement.create!(expense_record_id: "recExp1",
                                             budget_record_id: "recBud1",
                                             endorsed_by_person_id: "recPer1",
                                             endorsed_at: Time.current)
      attempt = BatchAttempt.create!(cost_centre: CostCentre.default, status: "completed",
                                     batch_record_id: "recBat1")
      store, = seeded_store
      import!(store: store, remap: true)
      assert_match(/\A\d+\z/, endorsement.reload.expense_record_id, "remapped to numeric")

      AirtableImporter.new(store: store, io: StringIO.new).unremap!

      endorsement.reload
      assert_equal "recExp1", endorsement.expense_record_id
      assert_equal "recBud1", endorsement.budget_record_id
      assert_equal "recPer1", endorsement.endorsed_by_person_id
      assert_equal "recBat1", attempt.reload.batch_record_id
    end
  end
end
