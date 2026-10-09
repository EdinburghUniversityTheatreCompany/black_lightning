module Reimbursements
  # Sends the producer and operator emails through Graph (GraphClient#send_mail) so they come
  # from the cost centre's send mailbox and land in its Sent Items, not from the website-noreply
  # address. Each message renders an ERB template (app/views/reimbursements/emails) in the bare
  # "reimbursements_mailer" layout through #renderer, which carries the mailer's host so *_url
  # helpers work outside a request.
  #
  # +cost_centre+ supplies the mailbox and all society-specific copy, and is added to every
  # template's assigns once, here. IT/credential alerts stay on ActionMailer
  # (ReimbursementsMailer): they have no cost-centre mailbox context.
  class Notifier
    def initialize(cost_centre:, graph: nil)
      @cost_centre = cost_centre
      @mailbox = cost_centre&.send_mailbox
      @graph = graph || GraphClient.new
    end

    # The producer methods take +greeting_name+ already derived (GreetingName.for), keeping this
    # boundary ActiveRecord-free. The +payee_name+ keys in the operator row hashes are still full names.

    # Producer: their expense was rejected on Review reject.
    def rejection(to:, greeting_name:, auto_number:, record_id:, amount:, budget_name:, description:, reason:)
      send_email(
        to: to,
        subject: "Your #{@cost_centre.name} expense ##{auto_number} was not approved",
        template: "reimbursements/emails/rejection",
        assigns: { greeting_name: greeting_name, auto_number: auto_number, record_id: record_id,
                   amount: amount, budget_name: budget_name, description: description, reason: reason }
      )
    end

    # Producer: one per payee for a processed BACS batch. The ONLY payment-side email a producer
    # gets: Reconcile sends none, because the actuals export it runs off arrives weeks after
    # the money did.
    def producer_notification(to:, greeting_name:, line_items:, bacs_date:, total:)
      count = line_items.size
      send_email(
        to: to,
        subject: "#{@cost_centre.subject_prefix} #{count} #{'expense'.pluralize(count)} " \
                 "submitted for payment",
        template: "reimbursements/emails/producer_notification",
        assigns: { greeting_name: greeting_name, line_items: line_items,
                   bacs_date: bacs_date, total: total }
      )
    end

    # Operator: pending submissions stuck awaiting approval past the threshold.
    def pending_reminder(recipients:, rows:, run_date:, threshold_days:)
      count = rows.size
      send_email(
        to: recipients,
        subject: "#{@cost_centre.subject_prefix} #{count} #{'submission'.pluralize(count)} " \
                 "awaiting approval (#{run_date})",
        template: "reimbursements/emails/pending_reminder",
        assigns: { rows: rows, run_date: run_date, threshold_days: threshold_days }
      )
    end

    # Budget owner: claims on their budgets awaiting their sign-off. Personal work, so +to+ and
    # +greeting_name+ rather than the shared-mailbox +recipients+. No age threshold, unlike
    # #pending_reminder: a claim awaiting sign-off is new work, named from the first run-day.
    def owner_sign_off_reminder(to:, greeting_name:, rows:, run_date:)
      count = rows.size
      send_email(
        to: to,
        subject: "#{@cost_centre.subject_prefix} #{count} #{'claim'.pluralize(count)} " \
                 "#{count == 1 ? 'needs' : 'need'} your sign-off (#{run_date})",
        template: "reimbursements/emails/owner_sign_off_reminder",
        assigns: { greeting_name: greeting_name, rows: rows, run_date: run_date }
      )
    end

    # Operator: the Approved queue, ready to batch. Rows with :flags need a look on Review first
    # but are still listed and counted: this is a reminder, not a gate. flagged_count is derived
    # here so the subject cannot drift from the table.
    def approved_ready(recipients:, expenses:, total:, run_date:, next_run_day: nil)
      count = expenses.size
      flagged = expenses.count { |expense| Array(expense[:flags]).any? }
      send_email(
        to: recipients,
        subject: "#{@cost_centre.subject_prefix} #{count} #{'expense'.pluralize(count)} " \
                 "ready to batch#{", #{flagged} flagged" if flagged.positive?} (#{run_date})",
        template: "reimbursements/emails/approved_ready",
        assigns: { expenses: expenses, total: total, run_date: run_date,
                   flagged_count: flagged, next_run_day: next_run_day }
      )
    end

    # Operator: the EUSA draft awaits review and send. +errors+ lists best-effort step failures
    # (upload, notification, flags): the draft is still valid, but the template must not claim
    # those steps succeeded.
    def batch_ready(recipients:, expenses:, total:, draft_link:, run_date:, batch_id:, errors: [])
      count = expenses.size
      send_email(
        to: recipients,
        subject: "#{@cost_centre.subject_prefix} Draft ready: #{count} " \
                 "#{'expense'.pluralize(count)} (#{run_date})",
        template: "reimbursements/emails/batch_ready",
        assigns: { expenses: expenses, total: total, draft_link: draft_link, run_date: run_date,
                   errors: errors, batch_id: batch_id }
      )
    end

    # Operator: the nightly run blew up; check logs and retry.
    def failure(recipients:, error_text:, run_date:)
      send_email(
        to: recipients,
        subject: "#{@cost_centre.subject_prefix} Batch processing FAILED: #{run_date}",
        template: "reimbursements/emails/failure",
        assigns: { error_text: error_text, run_date: run_date }
      )
    end

    private

    # Every template gets @cost_centre, so sign-off and contact details come from the sending centre.
    def send_email(to:, subject:, template:, assigns:)
      html = renderer.render(
        template: template, layout: "reimbursements_mailer",
        assigns: assigns.merge(subject: subject, cost_centre: @cost_centre).stringify_keys
      )
      result = @graph.send_mail(mailbox: @mailbox, to: Array(to), subject: subject, html: html)
      log_send(to: to, subject: subject, template: template)
      result
    end

    # Outside a request the default renderer answers *_url with http://example.org, so it takes
    # the mailer's host and protocol instead.
    def renderer
      url = Rails.application.config.action_mailer.default_url_options || {}
      ApplicationController.renderer.new(http_host: [ url.fetch(:host), url[:port] ].compact.join(":"),
                                         https: url[:protocol].to_s.start_with?("https"))
    end

    # Logged AFTER the send, never before. Every message passes this one chokepoint, so the log
    # lives here rather than at nine call sites. NotificationLog.record swallows its own
    # failures: an unlogged email that went out beats a logged one that did not. The KIND is the
    # template's basename, so a new message type logs itself.
    def log_send(to:, subject:, template:)
      NotificationLog.record(kind: File.basename(template.to_s), recipients: to,
                             subject: subject, cost_centre: @cost_centre)
    end
  end
end
