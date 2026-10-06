module ReimbursementsHelper
  # Modulus-check result => BadgeComponent variant and label.
  MODULUS_BADGE = {
    Reimbursements::ModulusCheck::VALID => { type: :success, label: "Valid" },
    Reimbursements::ModulusCheck::INVALID => { type: :danger, label: "Invalid" },
    Reimbursements::ModulusCheck::OUTSIDE_SPEC => { type: :warning, label: "Outside spec" }
  }.freeze

  # Modulus badge for a person's bank details. Pass the checker so requests share one
  # loaded rule set (and tests can inject a fake).
  def reimbursements_modulus_badge(person, checker: Reimbursements::ModulusCheck.default_checker)
    # Missing blocks approval as INVALID does, so it gets warning weight, not grey.
    return reimbursements_pill(:warning, "Missing") unless person.bank_details?

    modulus_pill(checker.check(person.sort_code, person.account_number))
  end

  # The badge for an expense's EFFECTIVE bank details (payee override, else the linked
  # person's). No modulus check on the international rail (it is a UK sort-code
  # algorithm); a stored IBAN has already passed mod-97, so its presence is the verdict.
  def reimbursements_effective_modulus_badge(expense, checker: Reimbursements::ModulusCheck.default_checker)
    return reimbursements_pill(:warning, "Missing") unless expense.effective_has_bank_details?
    return reimbursements_pill(:success, "IBAN") if expense.international?

    modulus_pill(Reimbursements::ReviewSupport.modulus_result(expense, checker))
  end

  # One Settings access-check row; SKIP means not configured.
  ACCESS_CHECK_BADGE = { ok: :success, fail: :danger, skip: :secondary }.freeze

  def reimbursements_access_check_badge(status)
    reimbursements_pill(ACCESS_CHECK_BADGE.fetch(status, :secondary), status.to_s.upcase)
  end

  # How long a claim has been with its owner, in days: "waiting 6 days" is what is judged.
  def reimbursements_waiting_for(submitted_at)
    return "just submitted" if submitted_at.blank?

    days = (Date.current - submitted_at.to_date).to_i
    case days
    when ..0 then "submitted today"
    when 1 then "waiting 1 day"
    else "waiting #{days} days"
    end
  end

  # The one reimbursements date format: ISO 8601, or "-" when blank. Takes a Date or Time.
  def reimbursements_date(value)
    return "-" if value.blank?

    value.strftime("%Y-%m-%d")
  end

  # "Waiting 6 days." for a claim on the owner gate. Empty, not "-" or "Waiting 0 days",
  # with no timestamp or submitted today: no delay to read, so nothing to print.
  def reimbursements_waiting_since(submitted_at)
    return "" if submitted_at.blank?

    days = (Date.current - submitted_at.to_date).to_i
    return "" unless days.positive?

    "Waiting #{pluralize(days, 'day')}."
  end

  # The one money format: "£12.50", or "-" for nil (never "£0.00"). Accepts a numeric or
  # a numeric string.
  def reimbursements_money(amount)
    return "-" if amount.nil?

    number_to_currency(amount, unit: "£")
  end

  # How much of an area's agreed total its lines use. A net basis that netted income off
  # prints its two halves, never the bare negative Area#allocated returns: a negative
  # means bad news elsewhere here, and the not-yet-allocated figure beside it would
  # reconcile only by subtracting a negative. The one derivation for the grouped index
  # and the area edit card.
  def reimbursements_area_allocation(area)
    unless area.net_basis? && area.allocated_income.positive?
      return reimbursements_money(area.allocated)
    end

    "#{reimbursements_money(area.allocated_spend)} of spend " \
      "less #{reimbursements_money(area.allocated_income)} of income"
  end

  # An amount as the value of a `step: 0.01` number input: 2dp, no delimiter or unit,
  # so deliberately not reimbursements_money (a number input rejects both).
  #
  # blank?, not nil?: an empty number input posts "", which format("%.2f", "") raises on,
  # so every refusal on such a form 500ed. Unreadable input is handed back as typed.
  def reimbursements_amount_value(amount)
    return if amount.blank?
    return format("%.2f", amount) if amount.is_a?(Numeric)

    parsed = ::Reimbursements::AmountParser.parse(amount)
    parsed ? format("%.2f", parsed) : amount.to_s
  end

  # The amount EUSA pays, in its currency. For an international claim that is the foreign
  # figure on their form, not the GBP one the budgets count: GBP beside a form saying EUR
  # reads as a discrepancy.
  def reimbursements_payment_amount(expense)
    return reimbursements_money(expense.amount) unless expense.international?

    currency = expense.foreign_currency.to_s
    symbol = CURRENCY_SYMBOLS.fetch(currency) { "#{currency} ".lstrip }
    "#{symbol}#{number_with_precision(expense.foreign_amount || 0, precision: 2, delimiter: ",")}"
  end

  # "$" and "kr" each cover several currencies, so those (and anything unlisted) print
  # the ISO code and a space: "CAD 500.00".
  CURRENCY_SYMBOLS = { "EUR" => "€", "GBP" => "£", "USD" => "US$", "JPY" => "¥" }.freeze

  def reimbursements_value(value)
    value.presence || "-"
  end

  # Choices for the cost centre of pasted rows that name none, on the Reconcile preview.
  # Deliberately no preselected default, even with one centre: the operator has to say.
  # The explicit skip choice makes that answerable, or another society's rows would be
  # parked under whichever centre was offered.
  def blank_cost_centre_options(cost_centres)
    [ [ "Choose a cost centre…", "" ] ] +
      cost_centres.map { |centre| [ "#{centre.name} (#{centre.eusa_code})", centre.id.to_s ] } +
      [ [ "Skip these rows: they are not ours", Reimbursements::ActualsAttribution::SKIP ] ]
  end

  # Who a submitter writes to about a claim finance has picked up: the CLAIM's own cost
  # centre (CostCentre.default is order(:id).first). An unplaced claim with several
  # centres configured gets plain words rather than a mailbox that won't recognise it.
  def reimbursements_contact_link(cost_centre = nil)
    centre = cost_centre || Reimbursements::CostCentre.sole_configured
    email = centre&.contact_email
    email.present? ? mail_to(email) : "the finance team"
  end

  # Every centre's receive mailbox, as a sentence: email-in attributes a receipt by the
  # mailbox it arrived at, so all of them are live.
  def reimbursements_receive_mailbox_links
    links = Reimbursements::CostCentre.order(:name).filter_map do |centre|
      mail_to(centre.receive_mailbox) if centre.receive_mailbox.present?
    end
    safe_join(links, " or ".html_safe) if links.any?
  end

  # Debits less credits, offsetting legs dropped: the netting the budget rollups use.
  def reimbursements_actuals_net(actuals)
    Reimbursements::EusaActual.net(actuals)
  end

  # The fx-rate controller's wiring for a claim's GBP amount field; none on the UK rail.
  def reimbursements_fx_rate_data(expense)
    return {} unless expense.international? && expense.foreign_amount.to_f.positive?

    { data: { controller: "fx-rate",
              fx_rate_foreign_amount_value: expense.foreign_amount.to_s,
              fx_rate_currency_value: expense.foreign_currency.to_s } }
  end

  # A converter prefilled with the invoice figure. An ordinary link: the portal makes no
  # request and stores no rate, so nothing here can go stale.
  def reimbursements_fx_converter_link(expense)
    return nil unless expense.international? && expense.foreign_amount.to_f.positive?

    url = "https://www.xe.com/currencyconverter/convert/?" +
          { Amount: expense.foreign_amount.to_s, From: expense.foreign_currency.to_s,
            To: "GBP" }.to_query
    link_to("Look up today's rate", url, class: "underline", target: "_blank", rel: "noopener")
  end

  # The unlink confirm dialog. Detaching a budget only re-attributes; detaching a claim
  # also reverses the settlement and returns it to Submitted. An international claim keeps
  # the corrected amount, as the estimate it replaced is not recorded.
  def reimbursements_unlink_confirm(actual)
    if actual.linked_expense_ids.any?
      "Unlink this row from its claim? The row stays on the ledger and goes back to needing "         "attention. If the claim was marked Paid by this match it returns to Submitted, and an "         "international claim keeps the amount EUSA actually charged."
    else
      "Unlink this row from its income line? The row stays on the ledger, that line stops "         "counting this money, and the row can then be split across several budgets."
    end
  end

  # The over-budget pill, or nothing. One derivation so the index and the overview cannot
  # disagree; BudgetHealth owns the rules.
  def reimbursements_budget_health_badge(budget)
    if budget.over_budget?
      reimbursements_pill(:danger, "Over budget")
    elsif budget.over_initial_budget?
      reimbursements_pill(:warning, "Over original budget")
    end
  end

  # The line's current plan: the latest forecast, else the initial figure. The fallback
  # is marked "(initial)", not hidden: the committee's opening figure and a figure finance
  # has revised are different claims.
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

  # A line's Remaining, as the index, the edit card and My Budgets print it. Nil means
  # nobody set a figure, and says so: a bare "-" reads as a broken column, and a 0 would
  # read as fully spent.
  def reimbursements_budget_remaining(budget)
    if budget.remaining.nil?
      # An income line's remaining is nil even with a figure set (its plan is money to
      # raise), so "No budget set" would contradict the Initial column.
      return content_tag(:span, "-", class: "text-gray-500",
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

  # Variance: positive (the plan grew past the agreed figure) is red, negative green,
  # zero (unrevised) neither.
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

  # Comma-joined owner names, resolving owner_ids against a {record_id => Person} lookup.
  def budget_owner_names(budget, people_by_id)
    budget.owner_ids.filter_map { |id| people_by_id[id]&.name.presence }.join(", ")
  end

  # An accessible disclosure badge (a button toggling a panel via popover_controller.js,
  # not a title= tooltip) listing an expense's reasons. +record_label+ (e.g. "#123")
  # scopes the accessible name to the row.
  def reimbursements_reasons_popover(reasons:, key:, label:, heading:, badge_type: :warning, record_label: nil)
    return "".html_safe if reasons.blank?

    panel_id = "reasons-#{key}"
    badge = BadgeComponent::STYLES.fetch(badge_type, BadgeComponent::STYLES[:secondary])
    accessible_name = record_label.present? ? "#{label} for #{record_label}" : label

    trigger = content_tag(:button, type: "button",
                          class: "inline-flex cursor-pointer items-center gap-1 rounded-full px-2 py-0.5 " \
                                 "text-xs font-medium #{badge}",
                          data: { popover_target: "trigger", action: "popover#toggle" },
                          # No aria-haspopup: a disclosure region, not a menu.
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

  # Producer-facing status wording ("where's my money?"); finance pages keep the raw status.
  PRODUCER_STATUS = {
    "Draft" => [ "Draft", "Only you can see this. Submit it when you're ready." ],
    "Pending" => [ "Waiting for review", "With the finance team, waiting to be checked." ],
    "Approved" => [ "Approved", "Checked and approved; waiting to be sent to EUSA for payment." ],
    "Submitted" => [ "Sent to EUSA", "Sent to the Students' Association (EUSA) for payment." ],
    "Paid" => [ "Paid", "Paid into your bank account." ],
    "Rejected" => [ "Rejected", "Not approved. See the reason on the row." ]
  }.freeze

  def reimbursements_producer_status_badge(status)
    label, tip = PRODUCER_STATUS.fetch(status, [ status, nil ])
    render(BadgeComponent.new(type: Reimbursements::Status.badge_variant(status)).with_content(label))
      .then { |html| tip ? content_tag(:span, html, title: tip, class: "inline-block") : html }
  end

  private

  def reimbursements_pill(type, label)
    render(BadgeComponent.new(type: type, pill: true).with_content(label))
  end

  def modulus_pill(result)
    spec = MODULUS_BADGE.fetch(result, MODULUS_BADGE[Reimbursements::ModulusCheck::OUTSIDE_SPEC])
    reimbursements_pill(spec[:type], spec[:label])
  end

  def variance_colour(variance)
    return nil if variance.zero?

    variance.positive? ? "text-danger" : "text-success"
  end

  def variance_title(variance)
    return "The current plan is still the initial budget" if variance.zero?

    variance.positive? ? "The plan is above the initial budget" : "The plan is below the initial budget"
  end
end
