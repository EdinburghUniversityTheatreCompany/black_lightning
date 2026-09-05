module Reimbursements
  ##
  # Renders the default EUSA finance email (subject + HTML body) for a batch. The
  # operator can edit the rendered subject + body on the Build Batch page before
  # the draft is created, so this only supplies the starting point.
  #
  # The body is an ActionController render of an ERB template (no layout) so it
  # can run outside a request (from BatchProcessor / a job).
  class EusaEmailComposer
    Email = Struct.new(:subject, :body_html, keyword_init: true)

    # Rails' dev-mode view annotations (config.action_view.
    # annotate_rendered_view_with_filenames) inject "<!-- BEGIN app/views/... -->"
    # comments that would otherwise land in the operator-editable body — and,
    # if left, in the real EUSA draft. Strip them defensively regardless of the
    # setting so the composed body is always clean.
    ANNOTATION_COMMENT = /<!--\s*(?:BEGIN|END)\s+\S+\.erb\s*-->\n?/

    # +cost_centre+ supplies both the EUSA code the subject quotes and the name
    # the body and sign-off use, so a termtime batch never says "Bedlam Fringe".
    # It supplies the greeting too. That fallback lives here rather than at the
    # call sites so the Build Batch form's default body and a background
    # BuildBatchJob with no overrides address the same EUSA contact.
    def compose(expenses:, bacs_date:, sender_name:, cost_centre:, eusa_contact_name: "")
      contact_name = eusa_contact_name.presence || cost_centre.eusa_contact_name
      total = expenses.sum { |expense| expense.amount || 0 }
      Email.new(
        subject: "#{cost_centre.name} BACS Request - #{bacs_date.iso8601} - #{cost_centre.eusa_code}",
        body_html: ApplicationController.render(
          template: "reimbursements/emails/eusa",
          layout: false,
          locals: { expenses: expenses, bacs_date: bacs_date, total: total,
                    expense_count: expenses.size, sender_name: sender_name,
                    cost_centre_name: cost_centre.name, eusa_contact_name: contact_name }
        ).gsub(ANNOTATION_COMMENT, "")
      )
    end
  end
end
