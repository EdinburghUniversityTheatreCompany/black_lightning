module Reimbursements
  ##
  # The default EUSA email (subject and HTML body) for a batch, which the
  # operator can edit on Build Batch. Renders outside a request, so a job can use it.
  class EusaEmailComposer
    Email = Struct.new(:subject, :body_html, keyword_init: true)

    # Rails' dev-mode view annotations (config.action_view.
    # annotate_rendered_view_with_filenames) inject "<!-- BEGIN app/views/... -->"
    # comments that must never reach the EUSA draft.
    ANNOTATION_COMMENT = /<!--\s*(?:BEGIN|END)\s+\S+\.erb\s*-->\n?/

    # +cost_centre+ supplies the subject's EUSA code, the name in the body and
    # sign-off, and the default greeting.
    def compose(expenses:, bacs_date:, sender_name:, cost_centre:, eusa_contact_name: "")
      contact_name = eusa_contact_name.presence || cost_centre.eusa_contact_name
      # Deliberately GBP across every claim: what the batch costs the budgets.
      # Each table row is in its own payment's currency.
      total = expenses.sum { |expense| expense.amount || 0 }
      international_count = expenses.count(&:international?)
      Email.new(
        subject: "#{cost_centre.name} BACS Request - #{bacs_date.iso8601} - #{cost_centre.eusa_code}",
        body_html: ApplicationController.render(
          template: "reimbursements/emails/eusa",
          layout: false,
          locals: { expenses: expenses, bacs_date: bacs_date, total: total,
                    expense_count: expenses.size, international_count: international_count,
                    sender_name: sender_name,
                    cost_centre_name: cost_centre.name, eusa_contact_name: contact_name }
        ).gsub(ANNOTATION_COMMENT, "")
      )
    end
  end
end
