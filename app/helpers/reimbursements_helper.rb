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
      return render(BadgeComponent.new(type: :secondary, pill: true).with_content("Missing"))
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

  # A GBP amount for the Budgets screens, or an em dash when not loaded (nil).
  def budget_money(amount)
    return "—" if amount.nil?

    number_to_currency(amount, unit: "£")
  end

  # Comma-joined owner names for a budget, resolving its owner_ids against a
  # {record_id => Person} lookup. Unknown ids are skipped.
  def budget_owner_names(budget, people_by_id)
    budget.owner_ids.filter_map { |id| people_by_id[id]&.name.presence }.join(", ")
  end
end
