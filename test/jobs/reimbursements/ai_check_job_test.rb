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
        @checked << [ expense.record_id, budgets.map(&:record_id) ]
        @result
      end
    end

    def verdict(status: "pass", comment: "Looks fine.", checked_at: Time.utc(2026, 7, 10, 12))
      AiChecker::Result.new(status: status, comment: comment, suggested_budget: "", checked_at: checked_at)
    end

    def seed_expense(**attrs)
      person = create_reimbursements_person
      @budget = create_reimbursements_budget
      create_reimbursements_expense(person: person, budget: @budget, **attrs)
    end

    teardown do
      AiCheckJob.checker_builder = -> { AiChecker.new }
    end

    test "writes the verdict back to the expense" do
      expense = seed_expense
      checker = FakeChecker.new(verdict(status: "fail", comment: "Amount mismatch."))
      AiCheckJob.checker_builder = -> { checker }

      AiCheckJob.perform_now(expense.record_id)

      expense.reload
      assert_equal "fail", expense.ai_check_status
      assert_equal "Amount mismatch.", expense.ai_comment
      assert expense.ai_checked_at.present?
      assert_equal [ [ expense.record_id, [ @budget.record_id ] ] ], checker.checked
    end

    test "broadcasts a live turbo-stream replace of the AI verdict when the check finishes" do
      expense = seed_expense
      AiCheckJob.checker_builder = -> { FakeChecker.new(verdict(status: "pass", comment: "Looks fine.")) }

      streams = capture_turbo_stream_broadcasts "reimbursements_review_ai" do
        AiCheckJob.perform_now(expense.record_id)
      end

      replace = streams.sole
      assert_equal "replace", replace["action"]
      assert_equal "ai_verdict_#{expense.record_id}", replace["target"]
      # The replacement carries the rendered verdict partial (the pass badge).
      assert_includes replace.to_html, "AI: Pass"
    end

    test "skips an expense that already has a verdict" do
      expense = seed_expense(ai_check_status: "pass", ai_comment: "Already done.")
      AiCheckJob.checker_builder = -> { raise "checker must not run" }

      AiCheckJob.perform_now(expense.record_id)

      assert_equal "Already done.", expense.reload.ai_comment
    end

    # Opening Review twice enqueues a second check for the same expense before
    # the first has written a verdict. Per-expense concurrency limiting serialises
    # the two runs, so by the time the second runs the first has written the
    # verdict and it no-ops — at most one Gemini call per expense.
    test "duplicate enqueues for the same expense trigger at most one Gemini check" do
      expense = seed_expense
      checker = FakeChecker.new(verdict(status: "pass", comment: "Looks fine."))
      AiCheckJob.checker_builder = -> { checker }

      perform_enqueued_jobs do
        AiCheckJob.perform_later(expense.record_id)
        AiCheckJob.perform_later(expense.record_id)
      end

      assert_equal [ expense.record_id ], checker.checked.map(&:first),
                   "the second serialised run must see the written verdict and no-op"
      assert_equal "pass", expense.reload.ai_check_status
    end

    test "does nothing when the expense is gone" do
      AiCheckJob.checker_builder = -> { raise "checker must not run" }

      assert_nothing_raised { AiCheckJob.perform_now("999999") }
    end

    # An "error" verdict means the checker itself couldn't run (a transient
    # Gemini blip, no API key) — not a real pass/fail — so it must NOT count
    # as "already checked", or a transient outage would permanently lock the
    # expense out of ever being rechecked.
    test "rechecks an expense stuck on a previous error verdict" do
      expense = seed_expense(ai_check_status: "error")
      checker = FakeChecker.new(verdict(status: "pass", comment: "Looks fine now."))
      AiCheckJob.checker_builder = -> { checker }

      AiCheckJob.perform_now(expense.record_id)

      assert_equal [ expense.record_id ], checker.checked.map(&:first)
      assert_equal "pass", expense.reload.ai_check_status
    end

    test "a broadcast failure is swallowed, not raised — the verdict is already durably written" do
      expense = seed_expense
      AiCheckJob.checker_builder = -> { FakeChecker.new(verdict(status: "pass")) }
      original_broadcast = Turbo::StreamsChannel.method(:broadcast_replace_to)
      Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to) { |*| raise "redis unavailable" }

      notified = capture_honeybadger_notices { AiCheckJob.perform_now(expense.record_id) }

      assert_equal "pass", expense.reload.ai_check_status,
                   "the verdict must still be written despite the broadcast failing"
      assert_equal 1, notified.size, "the broadcast failure must still be reported"
    ensure
      Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to, original_broadcast)
    end
  end
end
