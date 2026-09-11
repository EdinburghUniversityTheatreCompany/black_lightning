module ReimbursementsHelper
  # Maps a modulus-check result to a BadgeComponent variant + label.
  MODULUS_BADGE = {
    Reimbursements::ModulusCheck::VALID => { type: :success, label: "Valid" },
    Reimbursements::ModulusCheck::INVALID => { type: :danger, label: "Invalid" },
    Reimbursements::ModulusCheck::OUTSIDE_SPEC => { type: :warning, label: "Outside spec" }
  }.freeze

  # Live modulus badge for a person's bank details. Renders a neutral
  # "Missing" badge when they have none, otherwise a green/red/amber badge for
  # VALID / INVALID / OUTSIDE_SPEC. Pass the checker so requests share one
  # loaded rule set (and tests can inject a fake).
  def reimbursements_modulus_badge(person, checker: Reimbursements::ModulusCheck.default_checker)
    unless person.bank_details?
      # Missing bank details block approval just as hard as an INVALID check, so
      # give it the same warning weight — a neutral grey badge let it hide next
      # to the routine "Unverified" pill when scanning for who to chase.
      return render(BadgeComponent.new(type: :warning, pill: true).with_content("Missing"))
    end

    result = checker.check(person.sort_code, person.account_number)
    spec = MODULUS_BADGE.fetch(result, MODULUS_BADGE[Reimbursements::ModulusCheck::OUTSIDE_SPEC])
    render(BadgeComponent.new(type: spec[:type], pill: true).with_content(spec[:label]))
  end

  # A person-like value carrying an expense's EFFECTIVE bank details (payee
  # override if set, else the linked person's), so the same modulus badge helper
  # renders against the details the money will actually be paid to.
  EffectivePayee = Struct.new(:sort_code, :account_number) do
    def bank_details?
      sort_code.present? && account_number.present?
    end
  end

  def reimbursements_effective_modulus_badge(expense, checker: Reimbursements::ModulusCheck.default_checker)
    return reimbursements_iban_badge(expense) if expense.international?

    payee = EffectivePayee.new(expense.effective_sort_code, expense.effective_account_number)
    reimbursements_modulus_badge(payee, checker: checker)
  end

  # The international rail's equivalent signal. There is no modulus check to
  # run — it is a UK sort-code algorithm — and reading the UK pair for a payee
  # who has neither badged every international claim "Missing" while its IBAN
  # sat right there. A stored IBAN has already passed its mod-97 check on the
  # way in, so its presence IS the verdict.
  def reimbursements_iban_badge(expense)
    unless expense.effective_iban.present? && expense.effective_bic.present?
      return render(BadgeComponent.new(type: :warning, pill: true).with_content("Missing"))
    end

    render(BadgeComponent.new(type: :success, pill: true).with_content("IBAN"))
  end

  # Pill badge for one Settings access-check row: OK green, FAIL red, SKIP grey
  # (not configured, so nothing to test).
  ACCESS_CHECK_BADGE = { ok: :success, fail: :danger, skip: :secondary }.freeze

  def reimbursements_access_check_badge(status)
    type = ACCESS_CHECK_BADGE.fetch(status, :secondary)
    render(BadgeComponent.new(type: type, pill: true).with_content(status.to_s.upcase))
  end

  # The one date format for the whole reimbursements section: ISO 8601
  # (YYYY-MM-DD), or "-" when nil/blank. Accepts a Date or Time (the date part
  # is taken). Use this everywhere a reimbursements date is shown, so ad-hoc
  # strftime/iso8601/localize calls can't drift apart.
  def reimbursements_date(value)
    return "-" if value.blank?

    value.strftime("%Y-%m-%d")
  end

  # The one money format for the whole reimbursements section: a GBP amount as
  # "£12.50" (2dp, thousands-separated), or "-" when nil. Accepts a numeric or a
  # numeric string (some emails pre-format their amounts). The single definition
  # is what makes nil render "-" (not "£0.00", not "—") everywhere.
  def reimbursements_money(amount)
    return "-" if amount.nil?

    number_to_currency(amount, unit: "£")
  end

  # The same amount as the VALUE of a `step: 0.01` number input. A decimal
  # column hands the view a BigDecimal, whose to_s an input renders as "100.0"
  # or "12.5" — a pence column short of the figure printed everywhere else.
  # No delimiter and no unit: a number input rejects both, and a rejected value
  # renders as an empty box, so this is deliberately not reimbursements_money.
  #
  # blank?, not nil?: a re-rendered form hands back what the BROWSER posted, and
  # an empty number input posts "", which format("%.2f", "") raises on — so
  # every refusal on a form carrying an empty amount 500ed instead of stating
  # its reason. A typed value that is not a number is handed back as typed for
  # the same reason: losing the box is better than losing the page.
  def reimbursements_amount_value(amount)
    return if amount.blank?
    return format("%.2f", amount) if amount.is_a?(Numeric)

    parsed = ::Reimbursements::AmountParser.parse(amount)
    parsed ? format("%.2f", parsed) : amount.to_s
  end

  # The amount EUSA is being asked to PAY, in the currency they pay it in.
  #
  # For an international claim that is the foreign figure on their form, not
  # the GBP one our budgets count — quoting GBP in the covering email beside a
  # form that says EUR reads as a discrepancy in the paperwork, and the two
  # numbers are days of exchange-rate apart.
  def reimbursements_payment_amount(expense)
    return reimbursements_money(expense.amount) unless expense.international?

    "#{reimbursements_currency_symbol(expense.foreign_currency)}#{number_with_precision(
      expense.foreign_amount || 0, precision: 2, delimiter: ","
    )}"
  end

  # Only where the symbol is unambiguous in a British context. The Nordic
  # kroner all share "kr" and the dollars all share "$", so those keep their ISO
  # code: "CAD 500.00" is plainer than a "$" that could be four currencies.
  CURRENCY_SYMBOLS = { "EUR" => "€", "GBP" => "£", "USD" => "US$", "JPY" => "¥" }.freeze

  # Falls back to the ISO code plus a space ("SEK 12.50"), which is unambiguous
  # if unlovely — better than printing one currency's sign over another's figure.
  def reimbursements_currency_symbol(currency)
    CURRENCY_SYMBOLS.fetch(currency.to_s, "#{currency} ".lstrip)
  end

  # The one "no value here" glyph for the reimbursements section, matching what
  # reimbursements_date / reimbursements_money already render for nil. A view
  # hardcoding an em dash makes the same empty cell read "—" in one column and
  # "-" in the next.
  BLANK_VALUE = "-".freeze

  def reimbursements_value(value)
    value.presence || BLANK_VALUE
  end

  # Choices for "which cost centre do the pasted rows with no cost centre of
  # their own belong to?" on the Reconcile preview.
  #
  # There is deliberately NO pre-selected default, not even when a single cost
  # centre is configured: the operator has to say. The explicit "skip" choice is
  # what makes that demand answerable — facing another society's blank rows, an
  # operator with no way to say "not ours" would park them under whichever
  # centre the form offered.
  def blank_cost_centre_options(cost_centres)
    [ [ "Choose a cost centre…", "" ] ] +
      cost_centres.map { |centre| [ "#{centre.name} (#{centre.eusa_code})", centre.id.to_s ] } +
      [ [ "Skip these rows — they are not ours", Reimbursements::ActualsAttribution::SKIP ] ]
  end

  # Who a submitter writes to about a claim finance has already picked up.
  #
  # Addressed to THAT CLAIM's cost centre, which is the only mailbox whose
  # finance team can answer about it — CostCentre.default is order(:id).first,
  # so a termtime producer used to be sent to the Fringe mailbox. An unplaced
  # claim (no budget yet) has no centre to name, and with several configured
  # there is no honest single answer, so it falls back to plain words rather
  # than to a mailbox that will not recognise the claim.
  def reimbursements_contact_link(cost_centre = nil)
    centre = cost_centre || Reimbursements::CostCentre.sole_configured
    email = centre&.contact_email
    email.present? ? mail_to(email) : "the finance team"
  end

  # Every mailbox a receipt may be emailed to, as a sentence — email-in
  # attributes an inbound receipt by the mailbox it arrived at, so with two
  # cost centres both addresses are live and naming only the first would send a
  # termtime receipt into the Fringe queue.
  def reimbursements_receive_mailbox_links
    links = Reimbursements::CostCentre.order(:name).filter_map do |centre|
      mail_to(centre.receive_mailbox) if centre.receive_mailbox.present?
    end
    safe_join(links, " or ".html_safe) if links.any?
  end

  # Debits less credits over a set of EUSA ledger rows (offsetting legs
  # dropped) — the same netting the budget rollups use, so the overview's
  # unattributed totals can't disagree with the per-budget figures.
  def reimbursements_actuals_net(actuals)
    Reimbursements::EusaActual.net(actuals)
  end

  # Comma-joined owner names for a budget, resolving its owner_ids against a
  # {record_id => Person} lookup. Unknown ids are skipped.
  def budget_owner_names(budget, people_by_id)
    budget.owner_ids.filter_map { |id| people_by_id[id]&.name.presence }.join(", ")
  end

  # An accessible popover listing the reasons an expense needs attention /
  # completion. A focusable <button> badge carrying aria-expanded +
  # aria-controls, toggling a Popper-positioned panel of reasons (see
  # popover_controller.js) — a `title=` tooltip would be invisible to keyboard
  # and screen-reader users. Used on the Review card, the finance
  # expenses table and the producer's own expenses table so all three surface
  # the same reasons the same accessible way.
  #
  # +reasons+ the list of reason strings; +key+ a unique seed for the panel id
  # (an expense record_id); +label+ the badge text; +heading+ the panel heading.
  # +record_label+ scopes the trigger's accessible name to the specific record
  # it's for (e.g. "#123") — without it, every row on a list page announces the
  # identical "Needs attention"/"Needs completion" name with no way to tell
  # which record a screen-reader user is on. Falls back to the static +label+
  # alone for a single, unambiguous call site.
  def reimbursements_reasons_popover(reasons:, key:, label:, heading:, badge_type: :warning, record_label: nil)
    return "".html_safe if reasons.blank?

    panel_id = "reasons-#{key}"
    badge = BadgeComponent::STYLES.fetch(badge_type, BadgeComponent::STYLES[:secondary])
    accessible_name = record_label.present? ? "#{label} for #{record_label}" : label

    trigger = content_tag(:button, type: "button",
                          class: "inline-flex cursor-pointer items-center gap-1 rounded-full px-2 py-0.5 " \
                                 "text-xs font-medium #{badge}",
                          data: { popover_target: "trigger", action: "popover#toggle" },
                          # No aria-haspopup: this panel is a plain disclosure
                          # region (static text), not a menu — aria-haspopup
                          # ="true" would claim the "menu" pattern (arrow-key
                          # navigable menuitem children) this doesn't have.
                          aria: { expanded: "false", controls: panel_id, label: accessible_name }) do
      safe_join([ label, content_tag(:span, "▾", aria: { hidden: "true" }) ], " ")
    end

    panel = content_tag(:div, id: panel_id,
                        class: "hidden z-50 max-w-xs rounded border border-gray-200 bg-white p-2 " \
                               "text-xs text-gray-700 shadow-lg",
                        data: { popover_target: "panel" }) do
      safe_join([
        content_tag(:p, heading, class: "font-medium"),
        content_tag(:ul, safe_join(reasons.map { |reason| content_tag(:li, reason) }),
                    class: "mt-1 list-disc pl-4")
      ])
    end

    content_tag(:span, safe_join([ trigger, panel ]),
                class: "relative inline-block", data: { controller: "popover" })
  end

  # Producer-facing status wording. The stored status values answer the
  # SYSTEM's question ("Submitted" = batched to EUSA); a submitter's question
  # is "where's my money?", so the portal shows a plainer label with a tooltip.
  # Finance pages keep the raw status. Status.badge_variant still drives colour.
  PRODUCER_STATUS = {
    "Draft" => [ "Draft", "Only you can see this. Submit it when you're ready." ],
    "Pending" => [ "Waiting for review", "With the finance team, waiting to be checked." ],
    "Approved" => [ "Approved", "Checked and approved; waiting to be sent to EUSA for payment." ],
    "Submitted" => [ "Sent to EUSA", "Sent to the Students' Association (EUSA) for payment." ],
    "Paid" => [ "Paid", "Paid into your bank account." ],
    "Rejected" => [ "Rejected", "Not approved. See the reason on the row." ]
  }.freeze

  # A status badge with the producer-facing label + an explaining tooltip.
  def reimbursements_producer_status_badge(status)
    label, tip = PRODUCER_STATUS.fetch(status, [ status, nil ])
    render(BadgeComponent.new(type: Reimbursements::Status.badge_variant(status)).with_content(label))
      .then { |html| tip ? content_tag(:span, html, title: tip, class: "inline-block") : html }
  end
end
