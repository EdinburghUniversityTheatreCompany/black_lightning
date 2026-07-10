module Reimbursements
  ##
  # Operator-facing emails from the nightly auto-submit run (NightlyBatchJob),
  # ported from bedlam-bacs templates/operator_*.html. Unlike the producer /
  # EUSA mail, these go to the finance operators (whoever holds the finance
  # permission) via the app's ActionMailer stack rather than Microsoft Graph.
  #
  # Every argument is a primitive (strings, integers, a Date, and arrays of
  # hashes of those) so the nightly job can deliver_later without a PORO that
  # ActiveJob can't serialise.
  class OperatorMailer < ApplicationMailer
    # Pending submissions stuck awaiting approval past the reminder threshold.
    # +rows+: [{ auto_number:, payee_name:, amount:, age_days: }]
    def pending_reminder(recipients:, rows:, run_date:, threshold_days:)
      @rows = rows
      @run_date = run_date
      @threshold_days = threshold_days
      mail(to: recipients,
           subject: "[Bedlam BACS] #{rows.size} #{'submission'.pluralize(rows.size)} awaiting approval " \
                    "— #{Date.current.iso8601}")
    end

    # The batch couldn't auto-submit: some approved expenses need attention.
    # +issues+: [{ auto_number:, payee_name:, amount:, reason: }]
    def manual_review(recipients:, issues:, unblocked_count:, run_date:, next_run_day:)
      @issues = issues
      @unblocked_count = unblocked_count
      @run_date = run_date
      @next_run_day = next_run_day
      mail(to: recipients,
           subject: "[Bedlam BACS] Manual review needed — #{issues.size} #{'issue'.pluralize(issues.size)} " \
                    "— #{Date.current.iso8601}")
    end

    # All clear: the EUSA draft was created and awaits review + send.
    # +expenses+: [{ auto_number:, payee_name:, amount:, budget_name:, description: }]
    def batch_ready(recipients:, expenses:, total:, draft_link:, run_date:)
      @expenses = expenses
      @total = total
      @draft_link = draft_link
      @run_date = run_date
      mail(to: recipients,
           subject: "[Bedlam BACS] Draft ready — #{expenses.size} #{'expense'.pluralize(expenses.size)} " \
                    "— #{Date.current.iso8601}")
    end

    # The nightly run blew up; the operator needs to check logs and retry.
    def failure(recipients:, error_text:, run_date:)
      @error_text = error_text
      @run_date = run_date
      mail(to: recipients, subject: "[Bedlam BACS] Batch processing FAILED — #{Date.current.iso8601}")
    end
  end
end
