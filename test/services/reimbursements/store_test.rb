require "test_helper"

module Reimbursements
  class StoreTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # Fake Airtable client counting calls per table, compatible with Client's interface.
    class FakeClient
      attr_reader :list_calls, :created, :updated, :uploads

      def initialize(records_by_table)
        @records_by_table = records_by_table
        @list_calls = Hash.new(0)
        @created = []
        @updated = []
        @uploads = []
      end

      def list_records(table)
        @list_calls[table] += 1
        @records_by_table.fetch(table, [])
      end

      def create_record(table, fields)
        @created << [ table, fields ]
        { "id" => "recNew#{@created.size}", "fields" => fields }
      end

      def update_record(table, record_id, fields)
        @updated << [ table, record_id, fields ]
        { "id" => record_id, "fields" => fields }
      end

      def upload_attachment(record_id, **kwargs)
        @uploads << [ record_id, kwargs ]
        { "id" => record_id }
      end
    end

    def build_store(expenses: nil, people: nil, budgets: nil)
      records = {
        expenses: expenses || [ airtable_expense_record ],
        people: people || [ airtable_person_record ],
        budgets: budgets || [
          airtable_budget_record,
          airtable_budget_record(id: "recBud2", name: "Inactive", active: nil),
          airtable_budget_record(id: "recBud3", name: "Ticket income").tap do |r|
            r["fields"][FIELD_IDS[:budgets][:budget_type]] = "Income"
          end
        ]
      }
      client = FakeClient.new(records)
      store = Store.new(client: client, config: reimbursements_test_config,
                        cache: ActiveSupport::Cache::MemoryStore.new)
      [ store, client ]
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

    test "create_expense! busts the expense cache" do
      store, client = build_store

      store.expenses
      store.create_expense!(description: "Tape", status: "Pending")
      store.expenses

      assert_equal 1, client.created.size
      assert_equal 2, client.list_calls[:expenses], "expense cache must be busted by the write"
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
  end
end
