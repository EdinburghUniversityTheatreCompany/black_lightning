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
  # hands the result to +send_mail+. The templates (app/views/reimbursements/emails)
  # keep the copy the retired ActionMailer views used; assigns pass the same
  # instance variables those templates already reference.
  #
  # +mailbox+ is the sending cost centre's send_mailbox. Callers thread the
  # relevant cost centre's mailbox (CostCentre.default today). The IT/credential
  # alerts stay on ActionMailer (ReimbursementsMailer): they go to a configured
  # subcommittee address with no cost-centre mailbox context.
  class Notifier
    def initialize(mailbox:, graph: nil)
      @mailbox = mailbox
      @graph = graph || GraphClient.new
    end

    # Producer: their expense was rejected on Review reject.
    def rejection(to:, payee_name:, auto_number:, amount:, budget_name:, description:, reason:)
      send_email(
        to: to,
        subject: "Your Bedlam expense ##{auto_number} was not approved",
        template: "reimbursements/emails/rejection",
        assigns: { payee_name: payee_name, auto_number: auto_number, amount: amount,
                   budget_name: budget_name, description: description, reason: reason }
      )
    end

    # Payee: "you've been paid" once EUSA's actuals confirm payment (Reconcile apply).
    def payment_confirmation(to:, person:, expenses:)
      count = Array(expenses).size
      send_email(
        to: to,
        subject: "EUSA has paid your expense#{'s' if count > 1}",
        template: "reimbursements/emails/payment_confirmation",
        assigns: { person: person, expenses: Array(expenses) }
      )
    end

    # Producer: one notification per payee for a processed BACS batch.
    def producer_notification(to:, recipient_name:, line_items:, bacs_date:, total:)
      count = line_items.size
      send_email(
        to: to,
        subject: "[Bedlam Fringe] #{count} #{'expense'.pluralize(count)} submitted for payment",
        template: "reimbursements/emails/producer_notification",
        assigns: { recipient_name: recipient_name, line_items: line_items,
                   bacs_date: bacs_date, total: total }
      )
    end

    # Operator: pending submissions stuck awaiting approval past the threshold.
    def pending_reminder(recipients:, rows:, run_date:, threshold_days:)
      count = rows.size
      send_email(
        to: recipients,
        subject: "[Bedlam BACS] #{count} #{'submission'.pluralize(count)} awaiting approval " \
                 "— #{Date.current.iso8601}",
        template: "reimbursements/emails/pending_reminder",
        assigns: { rows: rows, run_date: run_date, threshold_days: threshold_days }
      )
    end

    # Operator: the batch couldn't auto-submit; some expenses need attention.
    def manual_review(recipients:, issues:, unblocked_count:, run_date:, next_run_day:)
      count = issues.size
      send_email(
        to: recipients,
        subject: "[Bedlam BACS] Manual review needed — #{count} #{'issue'.pluralize(count)} " \
                 "— #{Date.current.iso8601}",
        template: "reimbursements/emails/manual_review",
        assigns: { issues: issues, unblocked_count: unblocked_count, run_date: run_date,
                   next_run_day: next_run_day }
      )
    end

    # Operator: the Approved queue is clean and ready to batch. The nightly no
    # longer auto-builds, so this just prompts the operator to open Build Batch —
    # there's no draft link (nothing has been submitted yet).
    def approved_ready(recipients:, expenses:, total:, run_date:)
      count = expenses.size
      send_email(
        to: recipients,
        subject: "[Bedlam BACS] #{count} #{'expense'.pluralize(count)} ready to batch " \
                 "— #{Date.current.iso8601}",
        template: "reimbursements/emails/approved_ready",
        assigns: { expenses: expenses, total: total, run_date: run_date }
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
        subject: "[Bedlam BACS] Draft ready — #{count} #{'expense'.pluralize(count)} " \
                 "— #{Date.current.iso8601}",
        template: "reimbursements/emails/batch_ready",
        assigns: { expenses: expenses, total: total, draft_link: draft_link, run_date: run_date,
                   errors: errors }
      )
    end

    # Operator: the nightly run blew up; check logs and retry.
    def failure(recipients:, error_text:, run_date:)
      send_email(
        to: recipients,
        subject: "[Bedlam BACS] Batch processing FAILED — #{Date.current.iso8601}",
        template: "reimbursements/emails/failure",
        assigns: { error_text: error_text, run_date: run_date }
      )
    end

    private

    def send_email(to:, subject:, template:, assigns:)
      html = ApplicationController.render(template: template, layout: "reimbursements_mailer",
                                          assigns: assigns.merge(subject: subject).stringify_keys)
      @graph.send_mail(mailbox: @mailbox, to: Array(to), subject: subject, html: html)
    end
  end
end
