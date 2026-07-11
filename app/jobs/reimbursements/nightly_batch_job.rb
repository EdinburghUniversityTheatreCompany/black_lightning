module Reimbursements
  ##
  # Nightly auto-submit, ported from bedlam-bacs scripts/nightly_check.py +
  # nightly_support.py. Runs daily via Solid Queue (config/recurring.yml) and
  # acts per cost centre only on that centre's configured run-days
  # (CostCentre#nightly_due?, which also de-dupes so a run-day fires once).
  #
  # For each due cost centre:
  #   1. remind operators about Pending submissions stuck awaiting approval
  #      (>PENDING_REMINDER_DAYS) — these never reach the Approved queue.
  #   2. triage every Approved expense: ReviewSupport.needs_attention plus the
  #      AI verdict (fail / error / unchecked / pass-with-note all count as an
  #      issue). Any issue -> email the operator a manual-review breakdown and
  #      STOP (no batch this run).
  #   3. all clean -> email the operator a "ready to batch" alert listing the
  #      approved expenses + total. The nightly NO LONGER auto-builds or drafts:
  #      Build Batch is operator-initiated, so nothing is submitted here.
  # Failures go to Honeybadger + a failure email.
  #
  # Operator recipients: the users holding the finance permission
  # (`:manage, :reimbursements_finance`), overridable with the
  # REIMBURSEMENTS_OPERATOR_EMAIL env var. See #operator_emails.
  #
  # A +dry_run+ logs the same decisions without sending email or recording the
  # run — so it can be triggered safely to preview.
  class NightlyBatchJob < ApplicationJob
    queue_as :default
    limits_concurrency key: "reimbursements_nightly_batch"

    # A Pending submission awaiting approval longer than this gets a reminder.
    PENDING_REMINDER_DAYS = 3

    # Injection seams for tests (no mocking library in this suite).
    class_attribute :store_builder, default: -> { Store.new }
    class_attribute :graph_builder, default: -> { GraphClient.new }
    class_attribute :checker_builder, default: -> { ModulusCheck.default_checker }
    # Operator alerts send through Graph (Notifier#send_mail) from the cost
    # centre's send mailbox, so they land in its Sent Items.
    class_attribute :notifier_builder,
                    default: ->(mailbox:, graph:) { Notifier.new(mailbox: mailbox, graph: graph) }

    def perform(dry_run: false, today: Date.current)
      CostCentre.all.each { |cost_centre| run_for(cost_centre, dry_run: dry_run, today: today) }
    end

    private

    def store
      @store ||= store_builder.call
    end

    def modulus_checker
      @modulus_checker ||= checker_builder.call
    end

    def run_for(cost_centre, dry_run:, today:)
      unless cost_centre.nightly_due?(today)
        Rails.logger.info("Nightly: #{cost_centre.key} not due on #{today} — skipping")
        return
      end

      expenses = store.expenses
      remind_stale_pending(cost_centre, expenses.select(&:pending?), today: today, dry_run: dry_run)

      # TODO(mysql): scope Approved expenses per cost centre via budget->cost_centre.
      # Expenses carry no cost-centre link yet, so the Approved queue is global; if
      # every due cost centre triaged + alerted on it they'd all fire on the same
      # expenses. Until the link exists, only the primary/default cost centre acts
      # on the Approved set. Advisory-only — the nightly submits nothing now.
      return finish_no_work(cost_centre, today, dry_run) unless cost_centre == default_cost_centre

      approved = expenses.select { |expense| expense.status == Status::APPROVED }
      return finish_no_work(cost_centre, today, dry_run) if approved.empty?

      issues, clean = triage(approved)
      if issues.any?
        handle_issues(cost_centre, issues, clean.size, today, dry_run)
      else
        alert_ready(cost_centre, approved, today, dry_run)
      end
    rescue StandardError => e
      handle_failure(cost_centre, e, today, dry_run)
    end

    def default_cost_centre
      @default_cost_centre ||= CostCentre.default
    end

    # --- Stale pending reminder -------------------------------------------

    def remind_stale_pending(cost_centre, pending, today:, dry_run:)
      cutoff = today.to_time(:utc) - PENDING_REMINDER_DAYS.days
      stale = pending.select { |e| e.submitted_at && e.submitted_at <= cutoff }
                     .sort_by(&:submitted_at)
      return if stale.empty?

      rows = stale.map do |expense|
        { auto_number: expense.auto_number, payee_name: expense.person&.name.to_s,
          amount: format("%.2f", expense.amount || 0), age_days: pending_age_days(expense, today) }
      end
      Rails.logger.info("Nightly: #{rows.size} stale pending for #{cost_centre.key}")
      return if dry_run

      notify(cost_centre) do |emailer, to|
        emailer.pending_reminder(recipients: to, rows: rows, run_date: run_date(today),
                                 threshold_days: PENDING_REMINDER_DAYS)
      end
    end

    def pending_age_days(expense, today)
      return 0 if expense.submitted_at.nil?

      ((today.to_time(:utc) - expense.submitted_at) / 1.day).floor
    end

    # --- Triage approved expenses -----------------------------------------

    def triage(approved)
      budget_by_id = store.budgets.index_by(&:record_id)
      issues = []
      clean = []
      approved.each do |expense|
        reasons = issue_reasons(expense, budget_by_id)
        if reasons.empty?
          clean << expense
        else
          issues << { auto_number: expense.auto_number, payee_name: expense.effective_payee_name,
                      amount: format("%.2f", expense.amount || 0), reason: reasons.join("; ") }
        end
      end
      [ issues, clean ]
    end

    def issue_reasons(expense, budget_by_id)
      reasons = []
      if ReviewSupport.needs_attention(expense, budget_by_id, modulus_checker)
        reasons << "needs attention (no budget linked, missing bank details, receipts, or over budget)"
      end
      reasons.concat(ai_reasons(expense))
      reasons
    end

    # A pass with an informational note still stops the headless path: the
    # interactive Review UI would show it, so a human must glance at it here too.
    def ai_reasons(expense)
      case expense.ai_check_status
      when "fail"
        [ "AI review: #{expense.ai_comment.presence || 'AI flagged an issue'}" ]
      when "error"
        [ "AI check error during check" ]
      when "", nil
        [ "AI check not yet run" ]
      when "pass"
        expense.ai_comment.present? ? [ "AI note: #{expense.ai_comment}" ] : []
      else
        []
      end
    end

    # --- Outcomes ----------------------------------------------------------

    def finish_no_work(cost_centre, today, dry_run)
      Rails.logger.info("Nightly: no approved expenses for #{cost_centre.key}")
      cost_centre.record_nightly_run!(today) unless dry_run
    end

    def handle_issues(cost_centre, issues, unblocked_count, today, dry_run)
      Rails.logger.info("Nightly: #{issues.size} issue(s), #{unblocked_count} clean for #{cost_centre.key}")
      return if dry_run

      notify(cost_centre) do |emailer, to|
        emailer.manual_review(recipients: to, issues: issues, unblocked_count: unblocked_count,
                              run_date: run_date(today), next_run_day: next_run_day(cost_centre, today))
      end
      cost_centre.record_nightly_run!(today)
    end

    # The Approved queue is clean: alert the operator that N expenses are ready
    # to batch (they open Build Batch to create the draft). The nightly submits
    # nothing — no BatchProcessor, no draft — so there's no draft link here.
    def alert_ready(cost_centre, approved, today, dry_run)
      total = approved.sum { |expense| expense.amount || 0 }
      if dry_run
        Rails.logger.info("Nightly [DRY RUN]: would alert #{approved.size} approved expense(s) " \
                          "totalling £#{format('%.2f', total)} ready to batch for #{cost_centre.key}")
        return
      end

      Rails.logger.info("Nightly: #{approved.size} approved expense(s) ready to batch for #{cost_centre.key}")
      rows = approved.map do |expense|
        { auto_number: expense.auto_number, payee_name: expense.effective_payee_name,
          amount: format("%.2f", expense.amount || 0), budget_name: expense.budget&.name.to_s,
          description: expense.description.to_s }
      end
      notify(cost_centre) do |emailer, to|
        emailer.approved_ready(recipients: to, expenses: rows, total: format("%.2f", total),
                               run_date: run_date(today))
      end
      cost_centre.record_nightly_run!(today)
    end

    def handle_failure(cost_centre, error, today, dry_run)
      Rails.logger.error("Nightly: #{cost_centre.key} raised #{error.class}: #{error.message}")
      Honeybadger.notify(error, context: { source: "reimbursements_nightly_batch", cost_centre: cost_centre.key })
      return if dry_run

      notify(cost_centre) { |emailer, to| emailer.failure(recipients: to, error_text: error.message, run_date: run_date(today)) }
    end

    # --- Helpers -----------------------------------------------------------

    # Send an operator alert through Graph from the cost centre's send mailbox.
    # A Graph failure must never break the nightly run (or trip the surrounding
    # rescue into sending a spurious failure email), so it's rescued + logged.
    def notify(cost_centre)
      recipients = operator_emails
      if recipients.empty?
        Rails.logger.warn("Nightly: no operator recipients configured — email skipped")
        return
      end
      yield(notifier(cost_centre), recipients)
    rescue StandardError => e
      Rails.logger.error("Nightly: operator email failed for #{cost_centre.key} — #{e.message}")
      Honeybadger.notify(e, context: { source: "reimbursements_nightly_email", cost_centre: cost_centre.key })
    end

    def notifier(cost_centre)
      notifier_builder.call(mailbox: cost_centre.send_mailbox, graph: graph_builder.call)
    end

    # The finance operators: users granted the finance permission via the grid,
    # or a single override address for a shared finance inbox.
    def operator_emails
      override = ENV["REIMBURSEMENTS_OPERATOR_EMAIL"].presence
      return [ override ] if override

      Admin::Permission.where(action: "manage", subject_class: "reimbursements_finance")
                       .flat_map(&:roles).flat_map(&:users).uniq
                       .map(&:email).compact_blank
    end

    def run_date(today)
      today.strftime("%-d %B %Y")
    end

    def next_run_day(cost_centre, today)
      cost_centre.next_nightly_run_day(today)&.strftime("%A %-d %B")
    end
  end
end
