require "test_helper"

module Reimbursements
  class AiCheckJobTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # AiChecker stand-in returning a canned verdict and recording what it checked.
    class FakeChecker
      attr_reader :checked

      def initialize(result)
        @result = result
        @checked = []
      end

      def check(expense, budgets = [])
        @checked << [ expense.record_id, budgets ]
        @result
      end
    end

    def verdict(status: "pass", comment: "Looks fine.", checked_at: Time.utc(2026, 7, 10, 12))
      AiChecker::Result.new(status: status, comment: comment, suggested_budget: "", checked_at: checked_at)
    end

    def setup_store(expenses:)
      @store, @client = build_fake_store(expenses: expenses,
                                         people: [ airtable_person_record ],
                                         budgets: [ airtable_budget_record ])
      AiCheckJob.store_builder = -> { @store }
    end

    teardown do
      AiCheckJob.store_builder = -> { Store.new }
      AiCheckJob.checker_builder = -> { AiChecker.new }
    end

    test "writes the verdict back to the expense" do
      setup_store(expenses: [ airtable_expense_record(id: "recExp1") ])
      checker = FakeChecker.new(verdict(status: "fail", comment: "Amount mismatch."))
      AiCheckJob.checker_builder = -> { checker }

      AiCheckJob.perform_now("recExp1")

      table, record_id, fields = @client.updated.sole
      assert_equal :expenses, table
      assert_equal "recExp1", record_id
      assert_equal "fail", fields[FIELD_IDS[:expenses][:ai_check_status]]
      assert_equal "Amount mismatch.", fields[FIELD_IDS[:expenses][:ai_comment]]
      assert fields[FIELD_IDS[:expenses][:ai_checked_at]].present?
      assert_equal [ [ "recExp1", @store.active_budgets ] ], checker.checked
    end

    test "skips an expense that already has a verdict" do
      already = airtable_expense_record(id: "recExp1",
                                        overrides: { FIELD_IDS[:expenses][:ai_check_status] => "pass" })
      setup_store(expenses: [ already ])
      AiCheckJob.checker_builder = -> { raise "checker must not run" }

      AiCheckJob.perform_now("recExp1")

      assert_empty @client.updated
    end

    test "does nothing when the expense is gone" do
      setup_store(expenses: [])
      AiCheckJob.checker_builder = -> { raise "checker must not run" }

      assert_nothing_raised { AiCheckJob.perform_now("recGone") }
      assert_empty @client.updated
    end
  end
end
