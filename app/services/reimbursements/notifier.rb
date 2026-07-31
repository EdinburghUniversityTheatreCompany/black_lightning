module Reimbursements
  ##
  # Sends the producer- and operator-facing reimbursements emails through
  # Microsoft Graph (GraphClient#send_mail) so they genuinely originate from the
  # cost centre's send mailbox and land in its Sent Items — rather than through
  # ActionMailer / MailerSend from the generic website-noreply address.
  #
  # It mirrors EusaEmailComposer's render pattern: each message renders an ERB
  # template to an HTML string via ApplicationController.render (running outside
  # a request — from a controller action, BatchProcessor, or the nightly job),
  # wrapped in the "reimbursements_mailer" layout (its own minimal <!DOCTYPE>/
  # <head>/<title> wrapper — deliberately not the app's shared, fully-branded
  # mail layout, whose marketing tone doesn't fit a plain finance notice) and
  # hands the result to +send_mail+. Templates live in
  # app/views/reimbursements/emails.
  #
  # Callers pass the sending +cost_centre+: it supplies the send mailbox AND
  # every piece of society-specific copy (subject prefix, sign-offs, contact
  # address). It is threaded into the template assigns ONCE here, so no call site
  # has to pass a signature string. The IT/credential alerts stay on ActionMailer
  # (ReimbursementsMailer): they go to a configured subcommittee address with no
  # cost-centre mailbox context.
  class Notifier
    def initialize(cost_centre:, graph: nil)
      @cost_centre = cost_centre
      @mailbox = cost_centre&.send_mailbox
      @graph = graph || GraphClient.new
    end

    # The three producer methods take +greeting_name+ already derived by the
    # call site (GreetingName.for), keeping the person lookup out of the render
    # path and this boundary ActiveRecord-free. NB the +payee_name+ keys inside
    # the operator-alert row hashes below are a different thing: still full names.

    # Producer: their expense was rejected on Review reject.
    def rejection(to:, greeting_name:, auto_number:, amount:, budget_name:, description:, reason:)
      send_email(
        to: to,
        subject: "Your #{@cost_centre.name} expense ##{auto_number} was not approved",
        template: "reimbursements/emails/rejection",
        assigns: { greeting_name: greeting_name, auto_number: auto_number, amount: amount,
                   budget_name: budget_name, description: description, reason: reason }
      )
    end

    # Payee: "you've been paid" once EUSA's actuals confirm payment (Reconcile apply).
    def payment_confirmation(to:, greeting_name:, expenses:)
      count = Array(expenses).size
      send_email(
        to: to,
        subject: "EUSA has paid your expense#{'s' if count > 1}",
        template: "reimbursements/emails/payment_confirmation",
        assigns: { greeting_name: greeting_name, expenses: Array(expenses) }
      )
    end

    # Producer: one notification per payee for a processed BACS batch.
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

    # Operator: everything sitting in the Approved queue, ready to be built into
    # a batch. Rows carrying a non-empty :flags need a look on the Review page
    # first; they are still listed, and still counted in the total, because this
    # is a reminder and not a gate — the nightly submits nothing either way.
    #
    # flagged_count is derived here rather than passed in, so a caller cannot
    # desynchronise the subject line from the table underneath it.
    def approved_ready(recipients:, expenses:, total:, run_date:, next_run_day: nil)
      count = expenses.size
      flagged = expenses.count { |expense| expense[:flags].present? }
      send_email(
        to: recipients,
        subject: "#{@cost_centre.subject_prefix} #{count} #{'expense'.pluralize(count)} " \
                 "ready to batch#{", #{flagged} flagged" if flagged.positive?} (#{run_date})",
        template: "reimbursements/emails/approved_ready",
        assigns: { expenses: expenses, total: total, run_date: run_date,
                   flagged_count: flagged, next_run_day: next_run_day }
      )
    end

    # Operator: the EUSA draft was created and awaits review + send. +errors+
    # carries any best-effort step failures (SharePoint upload, producer
    # notification, batch flags) — the draft itself is still valid and ready to
    # send, but the template must not claim those steps all succeeded when
    # +errors+ is non-empty.
    def batch_ready(recipients:, expenses:, total:, draft_link:, run_date:, errors: [])
      count = expenses.size
      send_email(
        to: recipients,
        subject: "#{@cost_centre.subject_prefix} Draft ready: #{count} " \
                 "#{'expense'.pluralize(count)} (#{run_date})",
        template: "reimbursements/emails/batch_ready",
        assigns: { expenses: expenses, total: total, draft_link: draft_link, run_date: run_date,
                   errors: errors }
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

    # Every template gets @cost_centre for free, so its sign-off and contact
    # details come from the sending cost centre without each caller having to
    # remember to pass a name through.
    def send_email(to:, subject:, template:, assigns:)
      html = ApplicationController.render(
        template: template, layout: "reimbursements_mailer",
        assigns: assigns.merge(subject: subject, cost_centre: @cost_centre).stringify_keys
      )
      @graph.send_mail(mailbox: @mailbox, to: Array(to), subject: subject, html: html)
    end
  end
end
