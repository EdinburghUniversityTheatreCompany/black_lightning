module Reimbursements
  ##
  # Build Batch off the request: BatchProcessor#process can exceed the request
  # timeout. A double-click cannot double-submit: builds are serialised per cost
  # centre, and the job re-selects the Approved set at run time, so a serialised
  # second build finds nothing left and no-ops. Emails the operator the draft
  # link (Notifier#batch_ready) or the failure.
  class BuildBatchJob < Reimbursements::ApplicationJob
    queue_as :default

    # Well above the default 3-minute lock: a 200-row batch's uploads can take
    # longer, and a lock expiring mid-run lets a second build past single-flight.
    limits_concurrency to: 1, duration: 30.minutes, key: ->(*args) {
      params = args.last.is_a?(Hash) ? args.last : {}
      "reimbursements_build_batch_#{params[:cost_centre_key]}"
    }

    # Test seams (the suite has no mocking library).
    class_attribute :graph_builder, default: -> { GraphClient.new }
    class_attribute :processor_builder,
                    default: ->(store:, graph:, cost_centre:) {
                      BatchProcessor.new(store: store, graph: graph, cost_centre: cost_centre)
                    }
    # Alerts send from the cost centre's send mailbox, so they land in its Sent Items.
    class_attribute :notifier_builder,
                    default: ->(cost_centre:, graph:) { Notifier.new(cost_centre: cost_centre, graph: graph) }

    def perform(cost_centre_key:, bacs_date:, sender_name:, eusa_recipient:, operator_emails:,
                eusa_subject: nil, eusa_body_html: nil, attempt_id: nil)
      # The row the controller created at the click, by id: "the oldest
      # building row" mislabels History when builds race or a prior job died.
      attempt = attempt_id && BatchAttempt.find_by(id: attempt_id)

      cost_centre = CostCentre.find_by(key: cost_centre_key)
      if cost_centre.nil?
        Rails.logger.warn("Build batch: no cost centre #{cost_centre_key.inspect} — skipping")
        attempt&.resolve!(status: "failed", error_messages: "Cost centre #{cost_centre_key} no longer exists.")
        return
      end

      # A run with no click-time row (a direct perform_now) still leaves a trace.
      attempt ||= BatchAttempt.create!(cost_centre: cost_centre, bacs_date: parse_date(bacs_date),
                                       triggered_by_email: Array(operator_emails).compact_blank.first)
      # The claims this centre OWNS, not the screens' lenient filter (which
      # lets two centres build the same claim).
      approved = store.expenses_owned_by_cost_centre(cost_centre)
                      .select { |expense| expense.status == Status::APPROVED }
      if approved.empty?
        Rails.logger.info("Build batch: no approved expenses for #{cost_centre.key} — nothing to build")
        attempt.resolve!(status: "nothing_to_build")
        return
      end

      result = processor(cost_centre).process(
        expenses: approved, bacs_date: parse_date(bacs_date),
        sender_name: sender_name.presence || cost_centre.finance_sender_name,
        eusa_recipient: eusa_recipient,
        eusa_subject: eusa_subject, eusa_body_html: eusa_body_html
      )
      attempt.resolve!(status: result.success ? "completed" : "failed",
                       error_messages: Array(result.errors).join("\n"),
                       batch_record_id: result.batch_id)
      notify(cost_centre, result, approved, operator_emails)
    rescue GraphAuth::AuthError => e
      # A credential failure dooms every further Graph call, the operator email
      # included, so escalate straight to IT.
      Rails.logger.error("Build batch: Graph authentication failing for #{cost_centre_key} — #{e.message}")
      GraphAuthAlert.notify(e, source: "reimbursements_build_batch")
      attempt&.resolve!(status: "failed", error_messages: "Microsoft authentication failed: #{e.message}")
    end

    private

    # The processor and the notifier share one GraphClient (one OAuth token).
    def graph
      @graph ||= graph_builder.call
    end

    def processor(cost_centre)
      processor_builder.call(store: store, graph: graph, cost_centre: cost_centre)
    end

    def parse_date(value)
      value.is_a?(Date) ? value : Date.parse(value.to_s)
    rescue ArgumentError
      Date.current
    end

    # A Graph outage here must not fail the job: the batch already ran.
    def notify(cost_centre, result, approved, operator_emails)
      recipients = Array(operator_emails).compact_blank
      if recipients.empty?
        Rails.logger.warn("Build batch: no operator recipients — email skipped for #{cost_centre.key}")
        return
      end

      emailer = notifier_builder.call(cost_centre: cost_centre, graph: graph)
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
          amount: format("%.2f", expense.amount || 0), budget_name: expense.budget&.display_name.to_s,
          description: expense.description.to_s }
      end
    end

    def run_date(date)
      parse_date(date).strftime("%-d %B %Y")
    end
  end
end
