module Reimbursements
  ##
  # Interactive Build Batch, run in the background. Build Batch used to run
  # BatchProcessor#process inline in the request — the xlsx build, every receipt
  # upload to SharePoint, the EUSA draft and the producer emails — which could
  # exceed the Puma/proxy timeout, and a double-click built two batches / two
  # drafts / marked Submitted twice.
  #
  # This job runs the SAME BatchProcessor#process the nightly uses, off the
  # request. Two protections stop a double-submit:
  #
  #   * +limits_concurrency+ keyed on the cost centre serialises builds, so a
  #     double-click can't run two processes at once; the second waits.
  #   * the job re-selects the Approved expenses at run time. By the time a
  #     serialised second build runs, the first has marked them Submitted, so the
  #     Approved set is empty and the build cleanly no-ops.
  #
  # When the draft is ready it emails the operator the draft link (Notifier
  # #batch_ready, as the nightly does); a failed build emails Notifier#failure.
  # The controller enqueues this and redirects to History with a "building…"
  # flash — the operator watches History / their inbox, not a spinning request.
  class BuildBatchJob < Reimbursements::ApplicationJob
    queue_as :default

    # Serialise builds per cost centre: a double-click (or a rapid rebuild) can't
    # run two BatchProcessor#process calls at once, so it can't create two drafts
    # / two batches / mark Submitted twice. duration: is set well above the
    # default 3-minute lock TTL — BatchProcessor#process does per-expense
    # SharePoint uploads and a Graph draft create across a batch that can run to
    # 200 rows, plausibly exceeding 3 minutes on its own; a lock expiring
    # mid-run would let a concurrent second build past the single-flight
    # guarantee this concurrency key exists to enforce.
    limits_concurrency to: 1, duration: 30.minutes, key: ->(*args) {
      params = args.last.is_a?(Hash) ? args.last : {}
      "reimbursements_build_batch_#{params[:cost_centre_key]}"
    }

    SENDER_FALLBACK = "Bedlam Fringe Finance".freeze

    # Injection seams for tests (mirrors NightlyBatchJob; no mocking library).
    class_attribute :graph_builder, default: -> { GraphClient.new }
    class_attribute :processor_builder,
                    default: ->(store:, graph:, cost_centre:) {
                      BatchProcessor.new(store: store, graph: graph, cost_centre: cost_centre)
                    }
    # Operator alerts send through Graph (Notifier) from the cost centre's send
    # mailbox, so they land in its Sent Items — the same as the nightly.
    class_attribute :notifier_builder,
                    default: ->(mailbox:, graph:) { Notifier.new(mailbox: mailbox, graph: graph) }

    def perform(cost_centre_key:, bacs_date:, sender_name:, eusa_recipient:, operator_emails:,
                eusa_subject: nil, eusa_body_html: nil)
      cost_centre = CostCentre.find_by(key: cost_centre_key)
      return Rails.logger.warn("Build batch: no cost centre #{cost_centre_key.inspect} — skipping") if cost_centre.nil?

      attempt = attempt_for(cost_centre, bacs_date, operator_emails)
      approved = store.expenses.select { |expense| expense.status == Status::APPROVED }
      if approved.empty?
        Rails.logger.info("Build batch: no approved expenses for #{cost_centre.key} — nothing to build")
        attempt.resolve!(status: "nothing_to_build")
        return
      end

      result = processor(cost_centre).process(
        expenses: approved, bacs_date: parse_date(bacs_date),
        sender_name: sender_name.presence || SENDER_FALLBACK, eusa_recipient: eusa_recipient,
        eusa_subject: eusa_subject, eusa_body_html: eusa_body_html
      )
      attempt.resolve!(status: result.success ? "completed" : "failed",
                       error_messages: Array(result.errors).join("\n"),
                       batch_record_id: result.batch_id)
      notify(cost_centre, result, approved, operator_emails)
    rescue GraphAuth::AuthError => e
      # Unlike an ordinary Graph outage, a credential failure means every
      # further Graph call (including the operator notifier itself) would
      # fail identically — escalate straight to the IT subcommittee instead of
      # attempting a doomed operator email.
      Rails.logger.error("Build batch: Graph authentication failing for #{cost_centre_key} — #{e.message}")
      GraphAuthAlert.notify(e, source: "reimbursements_build_batch")
      attempt&.resolve!(status: "failed", error_messages: "Microsoft authentication failed: #{e.message}")
    end

    private

    # Memoized like +store+: graph_builder.call is invoked at two separate call
    # sites in a single run (the processor and the notifier), and each call
    # would otherwise mint a brand-new GraphClient — and a brand-new OAuth
    # token fetch — of its own.
    def graph
      @graph ||= graph_builder.call
    end

    def processor(cost_centre)
      processor_builder.call(store: store, graph: graph, cost_centre: cost_centre)
    end

    # BatchesController#create makes the attempt row at click time (so History
    # shows the build from the moment it's queued); pick up the oldest
    # unresolved one. A retry — or a direct perform_now with no controller —
    # has none, so create one here rather than lose the trace.
    def attempt_for(cost_centre, bacs_date, operator_emails)
      BatchAttempt.building.where(cost_centre: cost_centre).order(:created_at).first ||
        BatchAttempt.create!(cost_centre: cost_centre, bacs_date: parse_date(bacs_date),
                             triggered_by_email: Array(operator_emails).compact_blank.first)
    end

    def parse_date(value)
      value.is_a?(Date) ? value : Date.parse(value.to_s)
    rescue ArgumentError
      Date.current
    end

    # Email the operator who triggered the build: the draft link on success, the
    # errors on failure. A Graph outage here must never leave the job in a failed
    # state (the batch itself already ran), so it's rescued + logged.
    def notify(cost_centre, result, approved, operator_emails)
      recipients = Array(operator_emails).compact_blank
      if recipients.empty?
        Rails.logger.warn("Build batch: no operator recipients — email skipped for #{cost_centre.key}")
        return
      end

      emailer = notifier_builder.call(mailbox: cost_centre.send_mailbox, graph: graph)
      if result.success
        emailer.batch_ready(recipients: recipients, expenses: notification_rows(approved),
                            total: format("%.2f", result.total_amount || 0),
                            draft_link: result.eusa_draft_web_link, run_date: run_date(result.bacs_date),
                            errors: result.errors)
      else
        emailer.failure(recipients: recipients, error_text: Array(result.errors).join("\n"),
                        run_date: run_date(result.bacs_date))
      end
    rescue GraphAuth::AuthError => e
      Rails.logger.error("Build batch: Graph authentication failing for #{cost_centre.key} — #{e.message}")
      GraphAuthAlert.notify(e, source: "reimbursements_build_batch")
    rescue StandardError => e
      log_and_notify("Build batch: operator email failed for #{cost_centre.key} — #{e.message}", e,
                     context: { source: "reimbursements_build_batch_email", cost_centre: cost_centre.key })
    end

    def notification_rows(expenses)
      expenses.map do |expense|
        { auto_number: expense.auto_number, payee_name: expense.effective_payee_name,
          amount: format("%.2f", expense.amount || 0), budget_name: expense.budget&.name.to_s,
          description: expense.description.to_s }
      end
    end

    def run_date(date)
      parse_date(date).strftime("%-d %B %Y")
    end
  end
end
