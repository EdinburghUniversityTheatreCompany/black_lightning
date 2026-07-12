require "test_helper"

module Reimbursements
  class AiCheckJobTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers
    include Turbo::Broadcastable::TestHelper
    include ActiveJob::TestHelper

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

    test "broadcasts a live turbo-stream replace of the AI verdict when the check finishes" do
      setup_store(expenses: [ airtable_expense_record(id: "recExp1") ])
      AiCheckJob.checker_builder = -> { FakeChecker.new(verdict(status: "pass", comment: "Looks fine.")) }

      streams = capture_turbo_stream_broadcasts "reimbursements_review_ai" do
        AiCheckJob.perform_now("recExp1")
      end

      replace = streams.sole
      assert_equal "replace", replace["action"]
      assert_equal "ai_verdict_recExp1", replace["target"]
      # The replacement carries the rendered verdict partial (the pass badge).
      assert_includes replace.to_html, "AI: Pass"
    end

    test "skips an expense that already has a verdict" do
      already = airtable_expense_record(id: "recExp1",
                                        overrides: { FIELD_IDS[:expenses][:ai_check_status] => "pass" })
      setup_store(expenses: [ already ])
      AiCheckJob.checker_builder = -> { raise "checker must not run" }

      AiCheckJob.perform_now("recExp1")

      assert_empty @client.updated
    end

    # Opening Review twice enqueues a second check for the same expense before
    # the first has written a verdict. Per-expense concurrency limiting serialises
    # the two runs, so by the time the second runs the first has written the
    # verdict and it no-ops — at most one Gemini call per expense.
    test "duplicate enqueues for the same expense trigger at most one Gemini check" do
      setup_store(expenses: [ airtable_expense_record(id: "recExp1") ])
      checker = FakeChecker.new(verdict(status: "pass", comment: "Looks fine."))
      AiCheckJob.checker_builder = -> { checker }

      perform_enqueued_jobs do
        AiCheckJob.perform_later("recExp1")
        AiCheckJob.perform_later("recExp1")
      end

      assert_equal [ "recExp1" ], checker.checked.map(&:first),
                   "the second serialised run must see the written verdict and no-op"
      assert_equal 1, @client.updated.size
    end

    test "does nothing when the expense is gone" do
      setup_store(expenses: [])
      AiCheckJob.checker_builder = -> { raise "checker must not run" }

      assert_nothing_raised { AiCheckJob.perform_now("recGone") }
      assert_empty @client.updated
    end
  end
end
