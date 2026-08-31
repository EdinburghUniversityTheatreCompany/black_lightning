module Reimbursements
  ##
  # Nightly reminders. Runs daily via Solid Queue (config/recurring.yml) and
  # acts per cost centre only on that centre's configured run-days
  # (CostCentre#nightly_due?, which also de-dupes so a run-day fires once).
  #
  # It is a REMINDER job, not a gate: it submits nothing, builds no batch and
  # holds nothing back. Per due cost centre, over that centre's own claims (an
  # expense resolves its centre through its budget), it sends, independently:
  #   1. a pending reminder — Pending submissions stuck awaiting approval
  #      (>PENDING_REMINDER_DAYS); these never reach the Approved queue.
  #   2. an approved reminder — everything in the Approved queue, ready to be
  #      built into a batch. Claims that ReviewSupport.needs_attention flags are
  #      listed with their reasons rather than replacing the reminder, so one
  #      problem claim never hides the rest of the queue.
  # Either reminder is skipped when it has nothing to say. Failures go to
  # Honeybadger + a failure email.
  #
  # The run-day is recorded only when EVERY reminder this run decided to send
  # actually left the building — see #run_for. Recording it marks the day
  # handled forever (nightly_due? then skips it), and there is no retry queue
  # behind these alerts, so a half-sent run must be retried whole. The price is
  # uncapped duplicates of the reminder that DID work: a multi-day Graph outage
  # re-sends it every night. That is the intended direction — duplicates over
  # silence — so don't "fix" it by loosening the .all? in #deliver_reminders.
  #
  # Operator recipients: the members of the cost centre's own notification role
  # (CostCentre#notification_role), resolved through NotificationRecipients,
  # which keeps the whole-portal REIMBURSEMENTS_OPERATOR_EMAIL override ahead of
  # it. A centre whose role is empty sends nothing, warns, and does NOT record
  # the run-day, so it keeps alarming rather than going quiet.
  #
  # A +dry_run+ logs the same decisions without sending email or recording the
  # run — so it can be triggered safely to preview.
  class NightlyBatchJob < Reimbursements::ApplicationJob
    queue_as :default
    # duration: set well above the default 3-minute lock TTL — this reads every
    # Approved expense across every cost centre and sends operator emails,
    # plausibly exceeding 3 minutes; a lock expiring mid-run would let Solid
    # Queue's sweep allow a concurrent second run past the single-flight
    # guarantee this concurrency key exists to enforce.
    limits_concurrency key: "reimbursements_nightly_batch", duration: 30.minutes

    # A Pending submission awaiting approval longer than this gets a reminder.
    PENDING_REMINDER_DAYS = 3

    # Injection seams for tests (no mocking library in this suite).
    class_attribute :graph_builder, default: -> { GraphClient.new }
    class_attribute :checker_builder, default: -> { ModulusCheck.default_checker }
    # Operator alerts send through Graph (Notifier#send_mail) from the cost
    # centre's send mailbox, so they land in its Sent Items.
    class_attribute :notifier_builder,
                    default: ->(cost_centre:, graph:) { Notifier.new(cost_centre: cost_centre, graph: graph) }

    def perform(dry_run: false, today: Date.current)
      CostCentre.all.each { |cost_centre| run_for(cost_centre, dry_run: dry_run, today: today) }
    end

    private

    def modulus_checker
      @modulus_checker ||= checker_builder.call
    end

    # Memoized like +store+: notify(cost_centre) can run once per due cost
    # centre in a single job execution, and each call would otherwise mint a
    # brand-new GraphClient — and a brand-new OAuth token fetch — of its own,
    # even though the app-only Graph credential is the same across cost
    # centres.
    def graph
      @graph ||= graph_builder.call
    end

    # Recipients are resolved BEFORE anything is built, so an empty notification
    # role is reported as the configuration gap it is rather than discovered
    # halfway through. Crucially the run-day is NOT recorded in that case: the
    # old code returned "delivered" for no recipients, which marked the day
    # handled forever and lost the alert. Leaving it unrecorded means tomorrow's
    # run tries again and keeps alarming until somebody fills the role in.
    def run_for(cost_centre, dry_run:, today:)
      unless cost_centre.nightly_due?(today)
        Rails.logger.info("Nightly: #{cost_centre.key} not due on #{today} — skipping")
        return
      end

      recipients = NotificationRecipients.for(cost_centre)
      return warn_no_recipients(cost_centre) if recipients.empty?

      delivered = deliver_reminders(cost_centre, recipients, dry_run: dry_run, today: today)
      record_run(cost_centre, today) if delivered && !dry_run
    rescue StandardError => e
      handle_failure(cost_centre, recipients, e, today, dry_run)
    end

    def warn_no_recipients(cost_centre)
      Rails.logger.warn("Nightly: #{cost_centre.key} has no notification recipients — " \
                        "its reminders went nowhere. Add people to the " \
                        "#{cost_centre.notification_role&.name.inspect} role.")
      Honeybadger.event("reimbursements.nightly_no_recipients",
                        cost_centre: cost_centre.key,
                        notification_role: cost_centre.notification_role&.name)
      nil
    end

    # Both reminders must be ATTEMPTED even when the first fails to send. The
    # array literal is what enforces that: `a && b` would short-circuit and
    # silently drop the approved reminder whenever Graph fluffed the pending
    # one, so don't rewrite this into a boolean expression.
    def deliver_reminders(cost_centre, recipients, dry_run:, today:)
      claims = claims_for(cost_centre)
      [ remind_stale_pending(cost_centre, recipients, claims.select(&:pending?),
                             today: today, dry_run: dry_run),
        remind_approved(cost_centre, recipients, claims.select(&:approved?),
                        today: today, dry_run: dry_run) ].all?
    end

    # --- Which claims belong to which cost centre --------------------------
    # An expense carries no cost-centre column; it resolves one through its
    # budget. store.expenses already `includes(:budget)`, so this costs no extra
    # query however many centres there are — and it is memoized, so the whole
    # job reads the ledger once rather than once per centre.

    def claims_for(cost_centre)
      claims_by_cost_centre_id.fetch(cost_centre.id, [])
    end

    # A claim whose budget names no cost centre falls to the DEFAULT centre
    # rather than to nobody. Same leniency as DatabaseStore#in_year (a row with
    # no financial year belongs to the year being viewed) and the reconcile
    # matcher (a budget with no cost centre still matches). The asymmetry that
    # governs it: a claim reminded to the wrong centre's admins is visible and
    # correctable, whereas a claim reminded to nobody leaves a producer waiting
    # indefinitely with nothing on screen to explain it. Prefer the wrong
    # reminder over silence.
    #
    # NOT memoized with ||=: the store read can raise (that is what drives
    # handle_failure), and a rescued raise must not be cached as an empty
    # result for the centres that follow.
    def claims_by_cost_centre_id
      return @claims_by_cost_centre_id if defined?(@claims_by_cost_centre_id)

      default_id = CostCentre.default&.id
      @claims_by_cost_centre_id =
        store.expenses.group_by { |expense| expense.budget&.cost_centre_id || default_id }
    end

    # --- Stale pending reminder -------------------------------------------

    # Returns true when nothing needed sending or the alert went out; false only
    # when a send was attempted and failed (see #notify). run_for gates the
    # run-day record on it, so "nothing to say" must not read as a failure.
    def remind_stale_pending(cost_centre, recipients, pending, today:, dry_run:)
      cutoff = today.to_time(:utc) - PENDING_REMINDER_DAYS.days
      stale = pending.select { |e| e.submitted_at && e.submitted_at <= cutoff }
                     .sort_by(&:submitted_at)
      return true if stale.empty?

      rows = stale.map do |expense|
        { auto_number: expense.auto_number, payee_name: expense.person&.name.to_s,
          amount: format("%.2f", expense.amount || 0), age_days: pending_age_days(expense, today) }
      end
      Rails.logger.info("Nightly: #{rows.size} stale pending for #{cost_centre.key}")
      return true if dry_run

      notify(cost_centre, recipients) do |emailer, to|
        emailer.pending_reminder(recipients: to, rows: rows, run_date: run_date(today),
                                 threshold_days: PENDING_REMINDER_DAYS)
      end
    end

    def pending_age_days(expense, today)
      return 0 if expense.submitted_at.nil?

      ((today.to_time(:utc) - expense.submitted_at) / 1.day).floor
    end

    # --- Approved queue reminder ------------------------------------------

    # Everything in the Approved queue, in one reminder. Claims that
    # needs_attention flags are listed WITH their reasons rather than diverting
    # the whole run into a separate "manual review" email: the nightly submits
    # nothing, so holding the ready-to-batch list back over one problem claim
    # only hid the other claims from the operator.
    #
    # Same return contract as #remind_stale_pending.
    def remind_approved(cost_centre, recipients, approved, today:, dry_run:)
      if approved.empty?
        Rails.logger.info("Nightly: no approved expenses for #{cost_centre.key}")
        return true
      end

      rows = approved_rows(approved)
      total = approved.sum { |expense| expense.amount || 0 }
      flagged = rows.count { |row| Array(row[:flags]).any? }
      Rails.logger.info("Nightly: #{rows.size} approved expense(s) ready to batch " \
                        "(#{flagged} flagged) for #{cost_centre.key}")
      return true if dry_run

      notify(cost_centre, recipients) do |emailer, to|
        emailer.approved_ready(recipients: to, expenses: rows, total: format("%.2f", total),
                               run_date: run_date(today),
                               next_run_day: next_run_day(cost_centre, today))
      end
    end

    # Clean first, flagged last — the same order the Review page puts them in,
    # so the email and the screen don't disagree. What needs attention is
    # carried by the subject line and the intro, not by table position.
    def approved_rows(approved)
      budget_by_id = store.budgets.index_by(&:record_id)
      approved
        .map { |expense| approved_row(expense, budget_by_id) }
        .sort_by { |row| [ row[:flags].any? ? 1 : 0, row[:auto_number].to_i ] }
    end

    # :flags carries the real reasons rather than a canned "needs attention"
    # string the operator would have to go and decode. Always an Array, never
    # nil, so the template joins it unguarded.
    def approved_row(expense, budget_by_id)
      { auto_number: expense.auto_number, payee_name: expense.effective_payee_name,
        amount: format("%.2f", expense.amount || 0), budget_name: expense.budget&.name.to_s,
        description: expense.description.to_s,
        flags: ReviewSupport.needs_attention_reasons(expense, budget_by_id, modulus_checker) }
    end

    # --- Outcomes ----------------------------------------------------------

    # +recipients+ can be nil: the raise may have happened before they resolved.
    # There is nowhere to send a failure email in that case, and the report has
    # already gone to Honeybadger.
    def handle_failure(cost_centre, recipients, error, today, dry_run)
      log_and_notify("Nightly: #{cost_centre.key} raised #{error.class}: #{error.message}", error,
                     context: { source: "reimbursements_nightly_batch", cost_centre: cost_centre.key })
      return if dry_run

      recipients = Array(recipients).compact_blank
      return if recipients.empty?

      notify(cost_centre, recipients) do |emailer, to|
        emailer.failure(recipients: to, error_text: error.message, run_date: run_date(today))
      end
    end

    # --- Helpers -----------------------------------------------------------

    # Send an operator alert through Graph from the cost centre's send mailbox.
    # A Graph failure must never break the nightly run (or trip the surrounding
    # rescue into sending a spurious failure email), so it's rescued + logged.
    #
    # Returns true when the alert was sent, false when a send was attempted and
    # failed. run_for gates record_run on EVERY reminder returning true:
    # recording a run whose alert silently failed to send would lose that alert
    # forever, since nightly_due? would then treat the run-day as already
    # handled. The cost of the conjunction is that a run where one reminder sent
    # and the other failed re-sends the first one tomorrow — the right trade,
    # since these alerts are deliberately at-least-once.
    def notify(cost_centre, recipients)
      yield(notifier(cost_centre), recipients)
      true
    rescue GraphAuth::AuthError => e
      Rails.logger.error("Nightly: Graph authentication failing for #{cost_centre.key} — #{e.message}")
      GraphAuthAlert.notify(e, source: "reimbursements_nightly_batch")
      false
    rescue StandardError => e
      log_and_notify("Nightly: operator email failed for #{cost_centre.key} — #{e.message}", e,
                     context: { source: "reimbursements_nightly_email", cost_centre: cost_centre.key })
      false
    end

    # Record a completed run-day, but never let a failure here (a DB blip)
    # propagate into run_for's outer rescue — the alert this run-day's outcome
    # already sent successfully would otherwise get followed by a spurious
    # "FAILED" email on top of a real success.
    def record_run(cost_centre, today)
      cost_centre.record_nightly_run!(today)
    rescue StandardError => e
      log_and_notify(
        "Nightly: failed to record the run for #{cost_centre.key} after a successful alert: #{e.message}", e,
        context: { source: "reimbursements_nightly_record_run", cost_centre: cost_centre.key }
      )
    end

    def notifier(cost_centre)
      notifier_builder.call(cost_centre: cost_centre, graph: graph)
    end

    def run_date(today)
      today.strftime("%-d %B %Y")
    end

    def next_run_day(cost_centre, today)
      cost_centre.next_nightly_run_day(today)&.strftime("%A %-d %B")
    end
  end
end
