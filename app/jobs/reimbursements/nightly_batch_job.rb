module Reimbursements
  ##
  # Nightly reminders, per cost centre on its run-days (CostCentre#nightly_due?).
  # A reminder, not a gate: it submits nothing and builds no batch. Over each
  # centre's own claims it sends, independently:
  #   1. finance the Pending claims older than PENDING_REMINDER_DAYS, leaving
  #      out those still awaiting a budget owner;
  #   2. finance the whole Approved queue, flagged claims listed with reasons;
  #   3. each budget owner the claims awaiting their sign-off.
  #
  # The run-day is recorded only when every finance reminder sent, because
  # recording it marks the day handled forever. The price is re-sending the one
  # that worked: duplicates over silence, so don't loosen the .all? in
  # #deliver_reminders.
  #
  # A +dry_run+ logs the same decisions without sending or recording.
  class NightlyBatchJob < Reimbursements::ApplicationJob
    queue_as :default
    # Well above the default 3-minute lock: one expiring mid-run would let a
    # second run past the single-flight guarantee.
    limits_concurrency key: "reimbursements_nightly_batch", duration: 30.minutes

    PENDING_REMINDER_DAYS = 3

    # Test seams (the suite has no mocking library).
    class_attribute :graph_builder, default: -> { GraphClient.new }
    class_attribute :checker_builder, default: -> { ModulusCheck.default_checker }
    # Alerts send from the cost centre's send mailbox, so they land in its Sent Items.
    class_attribute :notifier_builder,
                    default: ->(cost_centre:, graph:) { Notifier.new(cost_centre: cost_centre, graph: graph) }

    def perform(dry_run: false, today: Date.current)
      CostCentre.all.each { |cost_centre| run_for(cost_centre, dry_run: dry_run, today: today) }
    end

    private

    def modulus_checker
      @modulus_checker ||= checker_builder.call
    end

    # One GraphClient (one OAuth token) per run, shared across cost centres.
    def graph
      @graph ||= graph_builder.call
    end

    # Recipients are resolved first. With none, warn and do NOT record the
    # run-day, so tomorrow retries rather than marking the alert handled.
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

    # The array literal makes sure both finance reminders are ATTEMPTED:
    # `a && b` would drop the second whenever the first failed.
    def deliver_reminders(cost_centre, recipients, dry_run:, today:)
      claims = claims_for(cost_centre)
      pending = claims.select(&:pending?)
      # One split for both reminders, so they agree on whose claim is whose.
      gated_ids = OwnerReview.unmet_gate_expense_ids(pending)
      awaiting_owner, finances = pending.partition { |e| gated_ids.include?(e.record_id) }
      # Best effort, OUTSIDE the .all?: one owner's dead address must not
      # withhold the run-day and re-send finance's reminders tomorrow.
      remind_budget_owners(cost_centre, awaiting_owner, today: today, dry_run: dry_run)
      [ remind_stale_pending(cost_centre, recipients, finances, today: today, dry_run: dry_run),
        remind_approved(cost_centre, recipients, claims.select(&:approved?),
                        today: today, dry_run: dry_run) ].all?
    end

    # --- Which claims belong to which cost centre --------------------------

    def claims_for(cost_centre)
      claims_by_cost_centre_id.fetch(cost_centre.id, [])
    end

    # A claim whose budget names no cost centre falls to the DEFAULT centre: a
    # reminder to the wrong centre is visible and correctable, one to nobody
    # leaves a producer waiting. Prefer the wrong reminder over silence.
    def claims_by_cost_centre_id
      @claims_by_cost_centre_id ||= begin
        default_id = CostCentre.default&.id
        store.expenses.group_by { |expense| expense.budget&.cost_centre_id || default_id }
      end
    end

    # --- Stale pending reminder -------------------------------------------

    # False only when a send failed; "nothing to say" counts as delivered.
    # +pending+ is finance's half of the Pending queue.
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

    # One email per owner, to their own address. No age threshold: a claim
    # awaiting your sign-off is new work, named every run-day until it is
    # endorsed or rejected. Best effort (see #deliver_reminders).
    def remind_budget_owners(cost_centre, awaiting_owner, today:, dry_run:)
      by_owner = claims_by_owner(awaiting_owner)
      return if by_owner.empty?

      Rails.logger.info("Nightly: #{awaiting_owner.size} claim(s) awaiting sign-off from " \
                        "#{by_owner.size} owner(s) for #{cost_centre.key}")
      return if dry_run

      # map, not a short-circuit: every owner is ATTEMPTED even after a failure.
      failed = by_owner.map { |owner, claims| remind_one_owner(cost_centre, owner, claims, today) }
                       .count(false)
      return if failed.zero?

      # Reported, or an address that never works leaves its owner un-nagged for good.
      Rails.logger.warn("Nightly: #{failed} owner sign-off reminder(s) failed to send " \
                        "for #{cost_centre.key}")
      Honeybadger.event("reimbursements.owner_reminder_failed",
                        cost_centre: cost_centre.key, failed: failed)
    end

    def remind_one_owner(cost_centre, owner, claims, today)
      rows = claims.sort_by { |claim| claim.submitted_at || Time.current }.map do |claim|
        { auto_number: claim.auto_number, payee_name: claim.person&.name.to_s,
          amount: format("%.2f", claim.amount || 0), budget_name: claim.budget&.display_name.to_s,
          description: claim.description.to_s, age_days: pending_age_days(claim, today) }
      end

      notify(cost_centre, [ owner.email ]) do |emailer, to|
        emailer.owner_sign_off_reminder(to: to, greeting_name: GreetingName.for(owner),
                                        rows: rows, run_date: run_date(today))
      end
    end

    # A claim with several owners is named to ALL of them: any one endorsement
    # satisfies the gate, so telling one would strand it while they are away.
    # Owners with no email are dropped here, so "nothing to send" is accurate.
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

    # The whole Approved queue in one reminder: a flagged claim is listed with
    # its reasons, never held back. Returns as #remind_stale_pending does.
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

    # Clean first, flagged last: the Review page's order.
    def approved_rows(approved)
      budget_by_id = store.budgets.index_by(&:record_id)
      approved
        .map { |expense| approved_row(expense, budget_by_id) }
        .sort_by { |row| [ row[:flags].any? ? 1 : 0, row[:auto_number].to_i ] }
    end

    # :flags is always an Array of reasons, so the template joins it unguarded.
    def approved_row(expense, budget_by_id)
      { auto_number: expense.auto_number, payee_name: expense.effective_payee_name,
        amount: format("%.2f", expense.amount || 0), budget_name: expense.budget&.display_name.to_s,
        description: expense.description.to_s,
        flags: ReviewSupport.needs_attention_reasons(expense, budget_by_id, modulus_checker) }
    end

    # --- Outcomes ----------------------------------------------------------

    # +recipients+ is nil when the raise came before they resolved; the report
    # has gone to Honeybadger either way.
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

    # Rescues every send failure, so it never trips run_for's rescue into a
    # spurious failure email. Returns false when the send failed, which stops
    # run_for recording the run-day.
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

    # A failure here (a DB blip) is reported but must not reach run_for's
    # rescue, which would follow a successful alert with a spurious FAILED email.
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
