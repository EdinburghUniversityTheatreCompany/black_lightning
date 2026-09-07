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
  #      Claims still awaiting a budget owner's sign-off are EXCLUDED: they are
  #      not finance's to act on yet, so nagging finance about them only buries
  #      the ones that are.
  #   2. an approved reminder — everything in the Approved queue, ready to be
  #      built into a batch. Claims that ReviewSupport.needs_attention flags are
  #      listed with their reasons rather than replacing the reminder, so one
  #      problem claim never hides the rest of the queue.
  #   3. an owner sign-off reminder — one email per BUDGET OWNER (not to the
  #      operator recipients) naming the claims waiting on them. This is the
  #      other half of excluding them above: the reminder moves to the person who
  #      can actually act, rather than disappearing.
  # Any reminder is skipped when it has nothing to say. Failures go to
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
  # Operator recipients: the cost centre's own notification email, resolved
  # through NotificationRecipients, which keeps the whole-portal
  # REIMBURSEMENTS_OPERATOR_EMAIL override ahead of it. A centre with none sends
  # nothing, warns, and does NOT record the run-day, so it keeps alarming rather
  # than going quiet. (The owner sign-off reminder is addressed separately, to
  # each budget owner.)
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
                        "its reminders went nowhere. Set its notification email in Settings.")
      Honeybadger.event("reimbursements.nightly_no_recipients", cost_centre: cost_centre.key)
      nil
    end

    # Both reminders must be ATTEMPTED even when the first fails to send. The
    # array literal is what enforces that: `a && b` would short-circuit and
    # silently drop the approved reminder whenever Graph fluffed the pending
    # one, so don't rewrite this into a boolean expression.
    def deliver_reminders(cost_centre, recipients, dry_run:, today:)
      claims = claims_for(cost_centre)
      pending = claims.select(&:pending?)
      # Split once, and share the split: the two reminders must never disagree
      # about which claims are finance's and which are still an owner's.
      gated_ids = OwnerReview.unmet_gate_expense_ids(pending)
      awaiting_owner, finances = pending.partition { |e| gated_ids.include?(e.record_id) }
      # Best effort, and deliberately OUTSIDE the .all? below: one budget owner's
      # dead address must not withhold the run-day, which would re-send FINANCE's
      # reminders tomorrow over a failure that was never theirs. Each failed send
      # is logged and reported, and the claim stays on Review's Awaiting owner tab
      # for finance to override either way, so nothing is silently lost.
      remind_budget_owners(cost_centre, awaiting_owner, today: today, dry_run: dry_run)
      [ remind_stale_pending(cost_centre, recipients, finances, today: today, dry_run: dry_run),
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
    # +pending+ here is finance's half of the Pending queue: claims still awaiting
    # a budget owner are handled by #remind_budget_owners instead.
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

    # --- Budget owner sign-off reminder -----------------------------------

    # One email per owner, listing every claim of theirs awaiting sign-off. Sent
    # to the OWNER's own address, not to the cost centre's notification email:
    # this is personal work on a specific person's budgets.
    #
    # No age threshold, unlike #remind_stale_pending — a claim awaiting your
    # sign-off is new work assigned to you, so it is named on the first due
    # run-day and re-named every run-day until it is endorsed or rejected.
    #
    # Returns nothing meaningful: best effort, and not part of the run-day
    # decision (see #deliver_reminders for why). An owner with no email address
    # is skipped outright — there is no address to retry tomorrow.
    def remind_budget_owners(cost_centre, awaiting_owner, today:, dry_run:)
      by_owner = claims_by_owner(awaiting_owner)
      return if by_owner.empty?

      Rails.logger.info("Nightly: #{awaiting_owner.size} claim(s) awaiting sign-off from " \
                        "#{by_owner.size} owner(s) for #{cost_centre.key}")
      return if dry_run

      # map, not each with a short-circuit: every owner is ATTEMPTED even when an
      # earlier send fails — the same reason #deliver_reminders builds an array
      # literal rather than a boolean expression.
      failed = by_owner.map { |owner, claims| remind_one_owner(cost_centre, owner, claims, today) }
                       .count(false)
      return if failed.zero?

      # Reported rather than swallowed: an address that never works would
      # otherwise leave those owners silently un-nagged for good.
      Rails.logger.warn("Nightly: #{failed} owner sign-off reminder(s) failed to send " \
                        "for #{cost_centre.key}")
      Honeybadger.event("reimbursements.owner_reminder_failed",
                        cost_centre: cost_centre.key, failed: failed)
    end

    def remind_one_owner(cost_centre, owner, claims, today)
      rows = claims.sort_by { |claim| claim.submitted_at || Time.current }.map do |claim|
        { auto_number: claim.auto_number, payee_name: claim.person&.name.to_s,
          amount: format("%.2f", claim.amount || 0), budget_name: claim.budget&.name.to_s,
          description: claim.description.to_s, age_days: pending_age_days(claim, today) }
      end

      notify(cost_centre, [ owner.email ]) do |emailer, to|
        emailer.owner_sign_off_reminder(to: to, greeting_name: GreetingName.for(owner),
                                        rows: rows, run_date: run_date(today))
      end
    end

    # Claims grouped by the owner who has to sign each one off. A claim with
    # several owners is named to ALL of them: any one endorsement satisfies the
    # gate (OwnerReview), so telling only one of them would leave the claim stuck
    # whenever that person is away.
    #
    # Owners with no email address are dropped here rather than deeper in, so
    # +remind_budget_owners+'s "nothing to send" check sees the truth.
    def claims_by_owner(awaiting_owner)
      return {} if awaiting_owner.empty?

      people = store.people.index_by(&:record_id)
      awaiting_owner.each_with_object(Hash.new { |h, k| h[k] = [] }) do |claim, by_owner|
        claim.budget.owner_ids.each do |owner_id|
          owner = people[owner_id]
          by_owner[owner] << claim if owner&.email.present?
        end
      end
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
