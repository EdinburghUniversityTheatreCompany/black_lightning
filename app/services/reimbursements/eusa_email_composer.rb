module Reimbursements
  ##
  # Renders the default EUSA finance email (subject + HTML body) for a batch,
  # ported from bedlam-bacs notifications.py / templates/eusa_email.html. The
  # operator can edit the rendered subject + body on the Build Batch page before
  # the draft is created, so this only supplies the starting point.
  #
  # The body is an ActionController render of an ERB template (no layout) so it
  # can run outside a request (from BatchProcessor / a job).
  class EusaEmailComposer
    Email = Struct.new(:subject, :body_html, keyword_init: true)

    def compose(expenses:, bacs_date:, sender_name:, eusa_code:, eusa_contact_name: "")
      total = expenses.sum { |expense| expense.amount || 0 }
      Email.new(
        subject: "Bedlam Fringe BACS Request - #{bacs_date.iso8601} - #{eusa_code}",
        body_html: ApplicationController.render(
          template: "reimbursements/emails/eusa",
          layout: false,
          locals: { expenses: expenses, bacs_date: bacs_date, total: total,
                    expense_count: expenses.size, sender_name: sender_name,
                    eusa_contact_name: eusa_contact_name }
        )
      )
    end
  end
end
