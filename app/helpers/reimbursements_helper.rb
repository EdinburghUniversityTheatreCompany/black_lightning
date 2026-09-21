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
  # How long a claim has been sitting with its owner. Days rather than a date,
  # because "waiting 6 days" is the thing being judged and a submitted date
  # makes the reader do the arithmetic.
  def reimbursements_waiting_for(submitted_at)
    return "just submitted" if submitted_at.blank?

    days = (Date.current - submitted_at.to_date).to_i
    case days
    when ..0 then "submitted today"
    when 1 then "waiting 1 day"
    else "waiting #{days} days"
    end
  end

  def reimbursements_date(value)
    return "-" if value.blank?

    value.strftime("%Y-%m-%d")
  end

  # "Waiting 6 days." from a submission timestamp — how long the producer has
  # been held up, which is the question asked of a claim sitting on the owner
  # gate. Empty (not "-", not "Waiting 0 days") for a claim with no timestamp
  # or submitted today: a figure nobody can read a delay off is noise on a
  # line that exists to report one.
  def reimbursements_waiting_since(submitted_at)
    return "" if submitted_at.blank?

    days = (Date.current - submitted_at.to_date).to_i
    return "" unless days.positive?

    "Waiting #{pluralize(days, 'day')}."
  end

  # The one money format for the whole reimbursements section: a GBP amount as
  # "£12.50" (2dp, thousands-separated), or "-" when nil. Accepts a numeric or a
  # numeric string (some emails pre-format their amounts). The single definition
  # is what makes nil render "-" (not "£0.00", not "—") everywhere.
  def reimbursements_money(amount)
    return "-" if amount.nil?

    number_to_currency(amount, unit: "£")
  end

  # How much of an area's agreed total has been split out into its lines, in
  # the one form every screen prints it: its two halves whenever a net basis
  # has netted income off the spend, and the single figure otherwise.
  #
  # The halves rather than the bare negative Area#allocated returns, because
  # you cannot allocate minus four hundred pounds, a negative money figure
  # means bad news everywhere else in this portal (Remaining is text-danger
  # when negative, a cell away on both surfaces), and the not-yet-allocated
  # figure beside it reconciles only by subtracting a negative. One derivation
  # for the grouped index and the area edit card, or the card keeps printing
  # what the index was changed to stop printing.
  def reimbursements_area_allocation(area)
    unless area.net_basis? && area.allocated_income.positive?
      return reimbursements_money(area.allocated)
    end

    "#{reimbursements_money(area.allocated_spend)} of spend " \
      "less #{reimbursements_money(area.allocated_income)} of income"
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

  # What unlinking this ledger row will do, for its confirm dialog.
  #
  # The two links are undone differently and the difference is the operator's
  # to know BEFORE they click: detaching a budget is a pure re-attribution,
  # while detaching a claim also reverses the settlement the match wrote and
  # sends the claim back to Submitted. An international claim keeps the
  # corrected amount either way — the estimate it replaced is not recorded
  # anywhere, so it cannot come back.
  def reimbursements_unlink_confirm(actual)
    if actual.linked_expense_ids.any?
      "Unlink this row from its claim? The row stays on the ledger and goes back to needing "         "attention. If the claim was marked Paid by this match it returns to Submitted, and an "         "international claim keeps the amount EUSA actually charged."
    else
      "Unlink this row from its income line? The row stays on the ledger, that line stops "         "counting this money, and the row can then be split across several budgets."
    end
  end

  # The over-budget / over-original-budget pill, or nothing. ONE derivation,
  # because the budgets index and the budget overview are two views of the
  # same lines and a line badged red on one and plain black on the other is
  # the disagreement the overview audit opened with. BudgetHealth owns the
  # rules; this owns how they read.
  def reimbursements_budget_health_badge(budget)
    if budget.over_budget?
      render(BadgeComponent.new(type: :danger, pill: true).with_content("Over budget"))
    elsif budget.over_initial_budget?
      render(BadgeComponent.new(type: :warning, pill: true).with_content("Over original budget"))
    end
  end

  # The line's CURRENT PLAN: the latest forecast, falling back to the initial
  # figure. One label and one figure on the index, the overview and the edit
  # card — they used to print "Current forecast" and "Projected", two names
  # for two different numbers, side by side in the same portal.
  #
  # The fallback is MARKED rather than hidden: "the committee's opening figure"
  # and "a figure finance has since revised" are different claims, and the
  # difference is the whole reason the forecast log exists.
  def reimbursements_budget_projected(budget)
    if budget.projected_amount.nil?
      return content_tag(:span, reimbursements_money(nil), class: "text-gray-400",
                         title: "No forecast has been logged and no initial budget was set.")
    end
    return reimbursements_money(budget.projected_amount) if budget.current_forecast

    content_tag(:span, title: "No forecast has been logged, so this is the initial budget.") do
      safe_join([ reimbursements_money(budget.projected_amount),
                  content_tag(:span, "(initial)", class: "text-xs text-gray-500") ], " ")
    end
  end

  # A budget line's Remaining, in the ONE form every screen prints it — the
  # budgets index, the budget edit card and a producer's My Budgets.
  #
  # Nil is the case this exists for. Budget#remaining is nil only when nobody
  # set a figure at all (no forecast and no initial budget), and a bare "-"
  # there reads as a broken column rather than as an unplanned line: it was on
  # every line of a freshly imported year. It says so instead. A 0 would be
  # worse still — everywhere else in this portal a Remaining of nothing means
  # fully spent.
  def reimbursements_budget_remaining(budget)
    if budget.remaining.nil?
      # An INCOME line's remaining is nil even when a figure IS set: its plan is
      # money to raise, so "what is left" means nothing on that side. Saying
      # "No budget set" there contradicted the £800.00 in the same row's
      # Initial column.
      return content_tag(:span, "—", class: "text-gray-500",
                         title: "Income is measured by what it raises (see EUSA actual), " \
                                "not by what is left of it.") if budget.income?

      return content_tag(:span, "No budget set", class: "text-gray-500",
                         title: "No forecast has been logged and no initial budget was set, " \
                                "so there is nothing left to be left of.")
    end

    content_tag(:span, reimbursements_money(budget.remaining),
                class: ("text-danger font-medium" if budget.remaining.negative?),
                title: ("Over budget: nothing left to spend" if budget.remaining.negative?))
  end

  # And its Variance, coloured the one way: POSITIVE means the plan grew past
  # the figure the committee agreed (the concerning direction) so it is red;
  # negative means it shrank, so green. Zero — the plan still being the agreed
  # figure, which is what an unrevised line reads — is neither.
  def reimbursements_budget_variance(budget)
    variance = budget.variance
    if variance.nil?
      return content_tag(:span, reimbursements_money(nil), class: "text-gray-400",
                         title: "No initial budget was agreed for this line, so there is " \
                                "nothing for the current plan to have drifted from.")
    end

    content_tag(:span, reimbursements_money(variance),
                class: variance_colour(variance), title: variance_title(variance))
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

  private

  def variance_colour(variance)
    return nil if variance.zero?

    variance.positive? ? "text-danger" : "text-success"
  end

  def variance_title(variance)
    return "The current plan is still the initial budget" if variance.zero?

    variance.positive? ? "The plan is above the initial budget" : "The plan is below the initial budget"
  end
end
