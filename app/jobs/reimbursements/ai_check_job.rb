module Reimbursements
  ##
  # Runs the AI expense check for one Pending expense and writes the verdict
  # back to Airtable, off the request thread. The Review page enqueues one of
  # these per unchecked Pending expense on load, so the operator isn't blocked
  # waiting on Gemini. Idempotent for a genuine pass/fail verdict: skips an
  # expense that already has one. An "error" verdict deliberately does NOT
  # count as checked (see ai_checked? below), so it can be rechecked once the
  # underlying problem clears.
  #
  # +store_builder+ / +checker_builder+ are the injection seams for tests.
  class AiCheckJob < Reimbursements::ApplicationJob
    queue_as :default

    # Serialise checks per expense (mirrors BuildBatchJob/NightlyBatchJob's
    # money-safety pattern): opening Review twice enqueues a second check for the
    # same expense before the first has written a verdict. Keying concurrency on
    # the record id makes the second run wait for the first, so it sees the
    # verdict already written and no-ops — no duplicate Gemini call, PROVIDED the
    # first run reached a genuine pass/fail verdict. If the first run instead
    # errored, the guard below intentionally lets the second (now-unblocked) run
    # proceed rather than no-op, so a transient Gemini blip gets a prompt retry —
    # the accepted cost is at most one extra Gemini call, bounded to the case
    # where two enqueues for the same expense race while the first is erroring.
    # duration: set above the default 3-minute lock TTL — RubyLLM's 120s
    # request_timeout plus its own retry attempts can plausibly exceed 3 minutes
    # on a single Gemini call.
    limits_concurrency to: 1, duration: 10.minutes,
                        key: ->(record_id) { "reimbursements_ai_check_#{record_id}" }

    class_attribute :checker_builder, default: -> { AiChecker.new }

    def perform(expense_record_id)
      expense = store.find_expense!(expense_record_id)
      # ai_checked? (not merely ai_check_status.present?) is deliberate: an
      # "error" verdict means the checker itself couldn't run (a transient
      # Gemini blip, a missing API key), not that the expense was actually
      # checked — treating it as done would permanently lock the expense out
      # of ever being rechecked once the underlying problem clears. A genuine
      # pass/fail verdict is the only thing this guard should skip.
      return if expense.nil? || expense.ai_checked?

      result = checker_builder.call.check(expense, store.active_budgets)
      # update_expense! returns the freshly-mapped expense (with the new verdict),
      # so the broadcast partial reflects the just-written status without a re-read.
      updated = store.update_expense!(expense_record_id,
                                      ai_check_status: result.status,
                                      ai_comment: result.comment,
                                      ai_checked_at: result.checked_at)
      broadcast_verdict(updated)
    end

    private

    # The verdict is already durably written by the time this runs; a failure
    # here is a live-UI nicety failing, not a checked-or-not correctness issue
    # (the next page load renders the true status straight from the store
    # regardless). Swallow rather than let it raise: retrying the whole job
    # would just re-run a completed check for nothing, since the idempotency
    # guard above would then skip the actual check on retry anyway.
    def broadcast_verdict(expense)
      broadcast_verdict!(expense)
    rescue StandardError => e
      Rails.logger.error("Reimbursements AI-verdict broadcast failed for #{expense.record_id}: #{e.message}")
      Honeybadger.notify(e, context: { expense_record_id: expense.record_id })
    end

    # Push the finished verdict onto the Review page live: replace the expense's
    # ai_verdict_<id> region (rendered on load as a "running…" placeholder) with
    # the badge + pass/fail/error explanation. The Review index subscribes via
    # turbo_stream_from "reimbursements_review_ai".
    def broadcast_verdict!(expense)
      Turbo::StreamsChannel.broadcast_replace_to(
        "reimbursements_review_ai",
        target: "ai_verdict_#{expense.record_id}",
        partial: "admin/reimbursements/review/ai_verdict",
        locals: { expense: expense }
      )
    end
  end
end
