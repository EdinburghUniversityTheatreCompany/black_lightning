require "test_helper"

module Reimbursements
  class StoreTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    def build_store(expenses: nil, people: nil, budgets: nil)
      build_fake_store(
        expenses: expenses || [ airtable_expense_record ],
        people: people || [ airtable_person_record ],
        budgets: budgets || [
          airtable_budget_record,
          airtable_budget_record(id: "recBud2", name: "Inactive", active: nil),
          airtable_budget_record(id: "recBud3", name: "Ticket income").tap do |r|
            r["fields"][FIELD_IDS[:budgets][:budget_type]] = "Income"
          end
        ]
      )
    end

    test "warm cache reads cost zero client calls" do
      store, client = build_store

      3.times { store.expenses }
      3.times { store.active_budgets }
      3.times { store.person_by_email("pat@example.com") }

      assert_equal 1, client.list_calls[:expenses]
      assert_equal 1, client.list_calls[:budgets]
      assert_equal 1, client.list_calls[:people]
    end

    test "expenses join people and budgets" do
      store, = build_store

      expense = store.expenses.sole
      assert_equal "Pat Producer", expense.person.name
      assert_equal "Props", expense.budget.name
    end

    test "expenses_for filters to one person and tolerates unlinked expenses" do
      orphan = airtable_expense_record(id: "recExp2", payee_id: nil)
      store, = build_store(expenses: [ airtable_expense_record, orphan ])

      mine = store.expenses_for("recPer1")
      assert_equal [ "recExp1" ], mine.map(&:record_id)
      assert_empty store.expenses_for(nil)
    end

    test "person_by_email matches case-insensitively" do
      store, = build_store

      assert_equal "recPer1", store.person_by_email("  PAT@Example.COM ").record_id
      assert_nil store.person_by_email("nobody@example.com")
    end

    test "active_budgets excludes inactive and income budgets" do
      store, = build_store

      assert_equal [ "Props" ], store.active_budgets.map(&:name)
    end

    test "find_expense! fetches a single record fresh on a cache miss" do
      store, client = build_store

      store.expenses # warm + memoize without recExpNew
      @late = airtable_expense_record(id: "recExpNew", description: "Late arrival")
      client.list_records(:expenses) << @late

      expense = store.find_expense!("recExpNew")

      assert_equal "Late arrival", expense.description
      assert_equal [ [ :expenses, "recExpNew" ] ], client.get_calls,
                   "must use the single-record endpoint, not a full re-list"
      assert_nil store.find_expense!("recMissing")
    end

    test "serves the backup copy when airtable is down" do
      store, client = build_store
      store.expenses # fills cache + backup

      cache = store.instance_variable_get(:@cache)
      cache.delete(Store::EXPENSES_KEY)
      client.define_singleton_method(:list_records) do |_table|
        raise Reimbursements::Airtable::Error.new("down", status: 503)
      end
      fresh_store = Store.new(client: client, config: reimbursements_test_config, cache: cache)

      assert_equal [ "recExp1" ], fresh_store.expenses.map(&:record_id)
    end

    test "remove_receipt! refuses to strip the last receipt" do
      store, client = build_store

      assert_raises(Store::LastReceiptError) { store.remove_receipt!("recExp1", "att1") }
      assert_empty client.updated
    end

    test "remove_receipt! allows removing a draft's last receipt" do
      store, client = build_store(expenses: [ airtable_expense_record(status: "Draft") ])

      store.remove_receipt!("recExp1", "att1")

      _table, _record_id, fields = client.updated.sole
      assert_equal [], fields[FIELD_IDS[:expenses][:receipt]]
    end

    test "create_expense! busts the expense cache" do
      store, client = build_store

      store.expenses
      store.create_expense!(description: "Tape", status: "Pending")
      store.expenses

      assert_equal 1, client.created.size
      assert_equal 2, client.list_calls[:expenses], "expense cache must be busted by the write"
    end

    test "remove_receipt! rewrites the survivors and busts the expense cache" do
      two_receipts = [
        { "id" => "att1", "filename" => "old.pdf", "url" => "https://x", "size" => 1, "type" => "application/pdf" },
        { "id" => "att2", "filename" => "new.pdf", "url" => "https://y", "size" => 1, "type" => "application/pdf" }
      ]
      store, client = build_store(expenses: [ airtable_expense_record(receipts: two_receipts) ])

      store.expenses
      store.remove_receipt!("recExp1", "att1")
      store.expenses

      _table, record_id, fields = client.updated.sole
      assert_equal "recExp1", record_id
      assert_equal [ { "id" => "att2" } ], fields[FIELD_IDS[:expenses][:receipt]]
      assert_equal 2, client.list_calls[:expenses], "expense cache must be busted by the removal"
    end

    test "attach_receipt! uploads and busts the expense cache" do
      store, client = build_store

      store.expenses
      store.attach_receipt!("recExp1", filename: "r.pdf", content_type: "application/pdf", bytes: "X")
      store.expenses

      assert_equal 1, client.uploads.size
      assert_equal 2, client.list_calls[:expenses]
    end

    test "update_person! busts the people cache" do
      store, client = build_store

      store.people
      store.update_person!("recPer1", sort_code: "112233")
      store.people

      assert_equal 1, client.updated.size
      assert_equal 2, client.list_calls[:people]
    end

    # --- EUSA Actuals -----------------------------------------------------

    test "actuals_for_month filters imported rows to that source month" do
      may = airtable_eusa_actual_record(id: "recActMay", source_month: "2026-05")
      apr = airtable_eusa_actual_record(id: "recActApr", source_month: "2026-04")
      store, = build_fake_store(eusa_actuals: [ may, apr ])

      assert_equal [ "recActMay" ], store.actuals_for_month("2026-05").map(&:record_id)
      assert_empty store.actuals_for_month("2026-01")
    end

    test "create_actual! writes a mapped row and busts the actuals cache" do
      store, client = build_fake_store(eusa_actuals: [ airtable_eusa_actual_record ])

      store.actuals_for_month("2026-05")
      actual = store.create_actual!(nominal_code: "439999", narrative: "Alice Producer",
                                    date: Date.new(2026, 5, 13), debit: BigDecimal("123.45"),
                                    source_month: "2026-05", imported_at: Time.utc(2026, 5, 14, 9))
      store.actuals_for_month("2026-05")

      table, fields = client.created.sole
      assert_equal :eusa_actuals, table
      assert_equal 123.45, fields[FIELD_IDS[:eusa_actuals][:debit]]
      assert_equal "2026-05-13", fields[FIELD_IDS[:eusa_actuals][:date]]
      assert_equal "2026-05-14T09:00:00Z", fields[FIELD_IDS[:eusa_actuals][:imported_at]]
      assert_equal "439999", actual.nominal_code
      assert_equal 2, client.list_calls[:eusa_actuals], "create must bust the actuals cache"
    end

    test "link_actual_to_expense! writes an expense link" do
      store, client = build_fake_store
      store.link_actual_to_expense!("recAct1", "recExp1")

      table, record_id, fields = client.updated.sole
      assert_equal :eusa_actuals, table
      assert_equal "recAct1", record_id
      assert_equal [ "recExp1" ], fields[FIELD_IDS[:eusa_actuals][:linked_expense]]
    end

    test "link_actual_to_budget! writes a budget link" do
      store, client = build_fake_store
      store.link_actual_to_budget!("recAct1", "recBud3")

      _table, _record_id, fields = client.updated.sole
      assert_equal [ "recBud3" ], fields[FIELD_IDS[:eusa_actuals][:linked_budget]]
    end

    # --- Batches -----------------------------------------------------------

    test "batches are cached and mapped" do
      store, client = build_fake_store(batches: [ airtable_batch_record ])

      3.times { store.batches }

      assert_equal 1, client.list_calls[:batches]
      assert_equal "BACS 2026-05-13", store.batches.sole.name
      assert_equal Date.new(2026, 5, 13), store.find_batch("recBat1").date_sent
    end

    test "create_batch! writes date + notes and busts the batch cache" do
      store, client = build_fake_store(batches: [])

      store.batches
      batch = store.create_batch!(date_sent: Date.new(2026, 5, 13), notes: "SP: url")
      store.batches

      table, fields = client.created.sole
      assert_equal :batches, table
      assert_equal "2026-05-13", fields[FIELD_IDS[:batches][:date_sent]]
      assert_equal "SP: url", fields[FIELD_IDS[:batches][:notes]]
      assert_equal batch.record_id, store.batches.first&.record_id.presence || batch.record_id
      assert_equal 2, client.list_calls[:batches], "create must bust the batch cache"
    end

    test "update_batch! and delete_batch! bust the cache" do
      store, client = build_fake_store(batches: [ airtable_batch_record ])

      store.batches
      store.update_batch!("recBat1", eusa_draft_created: true)
      store.delete_batch!("recBat1")

      assert fields_of(client.updated.sole)[FIELD_IDS[:batches][:eusa_draft_created]]
      assert_equal [ [ :batches, "recBat1" ] ], client.deleted
    end

    test "revert_expense_to_approved! clears the batch link, dates and offload flags" do
      submitted = airtable_expense_record(
        id: "recExp1", status: "Submitted",
        overrides: { FIELD_IDS[:expenses][:batch] => [ "recBat1" ],
                     FIELD_IDS[:expenses][:submitted_to_eusa_date] => "2026-05-13" }
      )
      store, client = build_store(expenses: [ submitted ])

      store.revert_expense_to_approved!("recExp1")

      _table, record_id, fields = client.updated.sole
      assert_equal "recExp1", record_id
      assert_equal "Approved", fields[FIELD_IDS[:expenses][:status]]
      assert_equal [], fields[FIELD_IDS[:expenses][:batch]], "batch link cleared with an empty array"
      assert_nil fields[FIELD_IDS[:expenses][:submitted_to_eusa_date]]
      refute fields[FIELD_IDS[:expenses][:receipts_offloaded]]
    end

    def fields_of(update_tuple)
      update_tuple.last
    end
  end
end
