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
    #
    # The gsub returns a plain String, which is why #compose marks the result
    # html_safe: it is markup this class generated — a template render plus an
    # operator note that #note_html has already ESCAPED — so the Build Batch
    # preview can render it without reaching for raw().
    ANNOTATION_COMMENT = /<!--\s*(?:BEGIN|END)\s+\S+\.erb\s*-->\n?/

    # What an operator may write into their note, and what each stands for.
    #
    # The Build Batch form used to hand them the whole rendered body as raw
    # HTML — including the generated claims table — on the one message that
    # asks EUSA to move money. A mistyped tag there breaks the table EUSA
    # reads, silently, and nothing in the portal would show it. So the operator
    # writes PLAIN TEXT with these placeholders, and the table, totals and
    # sign-off stay generated.
    #
    # Order is the order the list is shown in: the ones somebody actually wants
    # in a covering note first.
    SUBSTITUTIONS = %w[contact centre date count total sender].freeze

    # Who the email opens to when no contact name is set anywhere. The DEFAULT
    # lives here rather than only in the template, so the placeholder list on
    # the form shows what {{contact}} will actually put in the message — a
    # blank there read as "this expands to nothing".
    DEFAULT_CONTACT = "Finance Team".freeze

    # A placeholder that is not on the list is left EXACTLY as typed rather
    # than blanked. A note reading "{{invoce}}" is a typo the operator can see
    # in the preview; one silently replaced with nothing is a sentence with a
    # hole in it that reaches EUSA.
    PLACEHOLDER = /\{\{\s*([a-z_]+)\s*\}\}/

    # +cost_centre+ supplies both the EUSA code the subject quotes and the name
    # the body and sign-off use, so a termtime batch never says "Bedlam Fringe".
    # It supplies the greeting too. That fallback lives here rather than at the
    # call sites so the Build Batch form's default body and a background
    # BuildBatchJob with no overrides address the same EUSA contact.
    # +note+ is the operator's own covering message, in PLAIN TEXT with
    # {{placeholders}}. Blank means the template's default opening, which is
    # what a build with no overrides sends.
    def compose(expenses:, bacs_date:, sender_name:, cost_centre:, eusa_contact_name: "", note: nil)
      contact_name = eusa_contact_name.presence || cost_centre.eusa_contact_name
      # Deliberately GBP across every claim, international ones included: this
      # is what the batch costs the budgets, and it is the figure the operator
      # reconciles against. The per-row amounts in the table are each in the
      # currency of their own payment, which the body says.
      total = expenses.sum { |expense| expense.amount || 0 }
      international_count = expenses.count(&:international?)
      # The SAME derivation the form lists, so what the operator is shown a
      # placeholder expands to is what the email actually puts there.
      values = substitution_values(expenses: expenses, bacs_date: bacs_date,
                                   sender_name: sender_name, cost_centre: cost_centre,
                                   eusa_contact_name: contact_name)
      Email.new(
        subject: "#{cost_centre.name} BACS Request - #{bacs_date.iso8601} - #{cost_centre.eusa_code}",
        body_html: ApplicationController.render(
          template: "reimbursements/emails/eusa",
          layout: false,
          locals: { expenses: expenses, bacs_date: bacs_date, total: total,
                    expense_count: expenses.size, international_count: international_count,
                    sender_name: sender_name,
                    cost_centre_name: cost_centre.name, eusa_contact_name: contact_name,
                    note_html: note_html(note, values) }
        ).gsub(ANNOTATION_COMMENT, "").html_safe
      )
    end

    # What each placeholder would expand to for this batch, for the form to
    # list. Built from the same derivation #compose uses, so the list cannot
    # promise something the email then does differently.
    def substitution_values(expenses:, bacs_date:, sender_name:, cost_centre:,
                            eusa_contact_name: "")
      total = expenses.sum { |expense| expense.amount || 0 }
      {
        "contact" => eusa_contact_name.presence || cost_centre.eusa_contact_name.presence ||
          DEFAULT_CONTACT,
        "centre" => cost_centre.name,
        "date" => I18n.l(bacs_date, format: :long),
        "count" => expenses.size.to_s,
        "total" => ActiveSupport::NumberHelper.number_to_currency(total, unit: "£"),
        "sender" => sender_name.to_s
      }
    end

    private

    # The operator's note as HTML: ESCAPED first, then blank-line-separated
    # blocks become paragraphs. Nothing they type can introduce markup, which
    # is the whole point — a covering note is prose, and the one piece of this
    # email that is not generated should not also be the one piece that can
    # break it.
    def note_html(note, values)
      text = note.to_s.strip
      return nil if text.empty?

      expanded = text.gsub(PLACEHOLDER) { |match| values.fetch(Regexp.last_match(1), match) }
      paragraphs = ERB::Util.html_escape(expanded).split(/\r?\n\s*\r?\n/)
      markup = paragraphs.map { |para| "<p>#{para.gsub(/\r?\n/, '<br>')}</p>" }.join("\n")
      # Safe because the operator's text was escaped on the line above and the
      # only markup here is the <p> and <br> this method wrote itself. NOT
      # safe_join, which rubocop's Rails/OutputSafety autocorrect reaches for:
      # it is a view helper, and this is a PORO rendered from a job as often as
      # from a request.
      markup.html_safe # rubocop:disable Rails/OutputSafety
    end
  end
end
