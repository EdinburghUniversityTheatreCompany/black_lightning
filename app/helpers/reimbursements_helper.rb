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
    payee = EffectivePayee.new(expense.effective_sort_code, expense.effective_account_number)
    reimbursements_modulus_badge(payee, checker: checker)
  end

  # Maps an AI-check status to a BadgeComponent variant + display label. Keyed on
  # the lower-cased status so "Pass"/"pass" both resolve. Unknown/blank falls
  # through to a neutral secondary badge.
  AI_BADGE = {
    "pass" => { type: :success, label: "Pass" },
    "fail" => { type: :danger, label: "Fail" },
    "error" => { type: :warning, label: "Error" }
  }.freeze

  # A pill badge for an expense's AI check verdict, colour-coded so Pass reads
  # green, Fail red, Error amber and an unchecked expense stays neutral grey.
  # Used everywhere the AI status surfaces (finance table, edit page, review card)
  # so the colours never drift apart.
  def reimbursements_ai_badge(expense)
    status = expense.ai_check_status.to_s.strip
    spec = AI_BADGE[status.downcase]
    type = spec ? spec[:type] : :secondary
    label = spec ? spec[:label] : status.presence || "Unchecked"
    render(BadgeComponent.new(type: type, pill: true).with_content("AI: #{label}"))
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
  # is taken). Use this everywhere a reimbursements date is shown so the ~6
  # ad-hoc strftime/iso8601/localize formats never drift apart again.
  def reimbursements_date(value)
    return "-" if value.blank?

    value.strftime("%Y-%m-%d")
  end

  # The one money format for the whole reimbursements section: a GBP amount as
  # "£12.50" (2dp, thousands-separated), or "-" when nil. Accepts a numeric or a
  # numeric string (some emails pre-format their amounts). Consolidates the old
  # budget_money helper and the ad-hoc number_to_currency / number_with_precision
  # / "£%.2f" call sites, so nil renders "-" (not "£0.00", not "—") everywhere.
  def reimbursements_money(amount)
    return "-" if amount.nil?

    number_to_currency(amount, unit: "£")
  end

  # Comma-joined owner names for a budget, resolving its owner_ids against a
  # {record_id => Person} lookup. Unknown ids are skipped.
  def budget_owner_names(budget, people_by_id)
    budget.owner_ids.filter_map { |id| people_by_id[id]&.name.presence }.join(", ")
  end

  # An accessible popover listing the reasons an expense needs attention /
  # completion. Replaces the old `title=` tooltip (invisible to keyboard and
  # screen-reader users) with a focusable <button> badge that carries
  # aria-expanded + aria-controls and toggles a Popper-positioned panel of
  # reasons (see popover_controller.js). Used on the Review card, the finance
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
end
