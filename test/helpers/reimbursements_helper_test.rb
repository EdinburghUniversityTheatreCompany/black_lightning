require "test_helper"

class ReimbursementsHelperTest < ActionView::TestCase
  include ReimbursementsTestHelpers

  Expense = ::Reimbursements::Expense
  Person = ::Reimbursements::Person
  Budget = ::Reimbursements::Budget
  ModulusCheck = ::Reimbursements::ModulusCheck

  def person_with(sort_code: "08-99-99", account_number: "66374958")
    person = Person.new(name: "Pat Producer", email: "pat@example.com")
    person.build_payment_details(sort_code: sort_code, account_number: account_number)
    person
  end

  test "modulus badge renders a warning 'Missing' badge for a payee with no bank details" do
    # Missing blocks approval like INVALID, so it is a warning, not neutral.
    html = reimbursements_modulus_badge(person_with(sort_code: "", account_number: ""))
    assert_includes html, "Missing"
    assert_includes html, "text-warning"
  end

  test "modulus badge labels and colours each verdict" do
    { ModulusCheck::VALID => %w[Valid text-success],
      ModulusCheck::INVALID => %w[Invalid text-danger],
      ModulusCheck::OUTSIDE_SPEC => [ "Outside spec", "text-warning" ] }.each do |result, (label, colour)|
      html = reimbursements_modulus_badge(person_with, checker: FakeModulusChecker.new("66374958" => result))
      assert_includes html, label, result.inspect
      assert_includes html, colour, result.inspect
    end
  end

  test "effective modulus badge checks the expense's EFFECTIVE bank details, not the linked person's" do
    person = person_with(sort_code: "", account_number: "") # no bank details of their own
    expense = Expense.new(status: "Pending", person: person,
                          sort_code_override: "20-20-20", account_number_override: "50502366")

    html = reimbursements_effective_modulus_badge(expense, checker: FakeModulusChecker.new("50502366" => ModulusCheck::VALID))

    assert_includes html, "Valid", "the override bank details are present, so this must not fall back to Missing"
  end

  test "effective modulus badge falls back to Missing when there's no override and no linked person" do
    expense = Expense.new(status: "Pending", person: nil)

    html = reimbursements_effective_modulus_badge(expense)

    assert_includes html, "Missing"
  end

  test "access check badge maps ok/fail/skip, and anything else to secondary" do
    { ok: %w[OK text-success], fail: %w[FAIL text-danger],
      skip: %w[SKIP text-gray-700], weird: %w[WEIRD text-gray-700] }.each do |status, (label, colour)|
      html = reimbursements_access_check_badge(status)
      assert_includes html, label, status.inspect
      assert_includes html, colour, status.inspect
    end
  end

  test "budget_owner_names comma-joins the owners' names, skipping a blank one" do
    budget = Budget.new(name: "Props")
    budget.own_owners = [ person_with, Person.new(name: "", email: "nameless@example.com"),
                          Person.new(name: "Alex", email: "alex@example.com") ]

    assert_equal "Pat Producer, Alex", budget_owner_names(budget)
  end

  # [label, value, selected?] for each option.
  def option_rows(html)
    Nokogiri::HTML::DocumentFragment.parse(html).css("option")
                                    .map { |option| [ option.text, option["value"], option.key?("selected") ] }
  end

  test "reimbursements_budget_options keeps a claim's own line when it is no longer offered" do
    offered = create_reimbursements_budget(name: "Props")
    retired = create_reimbursements_budget(name: "Old set", active: false)

    assert_equal [ [ "Old set", retired.record_id, true ], [ "Props", offered.record_id, false ] ],
                 option_rows(reimbursements_budget_options([ offered ], retired))
    assert_equal [ [ "Props", offered.record_id, true ] ],
                 option_rows(reimbursements_budget_options([ offered ], offered))
    assert_equal [ [ "Props", offered.record_id, false ] ],
                 option_rows(reimbursements_budget_options([ offered ], nil))
  end

  test "reimbursements_date is ISO 8601, or a dash when blank" do
    { Date.new(2026, 7, 11) => "2026-07-11", Time.utc(2026, 7, 11, 9, 30) => "2026-07-11",
      nil => "-", "" => "-" }.each do |value, expected|
      assert_equal expected, reimbursements_date(value), value.inspect
    end
  end

  test "reimbursements_money is GBP to 2dp, zero included, and a dash for nil" do
    { 12.5 => "£12.50", 0 => "£0.00", "1234.50" => "£1,234.50", nil => "-" }.each do |amount, expected|
      assert_equal expected, reimbursements_money(amount), amount.inspect
    end
  end

  # The allocation prints on the grouped index and the area edit card.
  def netted_area(spend: 400, income: 800, basis: "net")
    area = create_reimbursements_area(name: "Committee", initial_budget: 1_000,
                                      budget_basis: basis)
    create_reimbursements_budget(name: "Socials", area: area, initial_budget: spend)
    create_reimbursements_budget(name: "Raffle", area: area, initial_budget: income,
                                 budget_type: "Income")
    area
  end

  test "reimbursements_area_allocation prints a netted allocation as its two halves" do
    assert_equal "£400.00 of spend less £800.00 of income",
                 reimbursements_area_allocation(netted_area)
  end

  test "reimbursements_area_allocation states a spend cap as one figure" do
    # A spend cap leaves income out, so there are no halves.
    assert_equal "£400.00", reimbursements_area_allocation(netted_area(basis: "expenses"))
  end

  test "reimbursements_area_allocation states a net area with no income as one figure" do
    assert_equal "£400.00", reimbursements_area_allocation(netted_area(income: 0))
  end

  # A browser posts "" for an empty number input; format("%.2f", "") raised, so refusals 500ed.
  test "reimbursements_amount_value is a number input's value: 2dp, no delimiter, blank as nil, unreadable as typed" do
    { BigDecimal("100") => "100.00", BigDecimal("12.5") => "12.50", BigDecimal("1234.5") => "1234.50",
      nil => nil, "" => nil, "£1,200" => "1200.00", "not a number" => "not a number" }.each do |value, expected|
      actual = reimbursements_amount_value(value)
      expected.nil? ? assert_nil(actual, value.inspect) : assert_equal(expected, actual, value.inspect)
    end
  end

  test "reasons_popover is blank when there are no reasons" do
    assert_equal "", reimbursements_reasons_popover(reasons: [], key: "x", label: "Needs attention",
                                                     heading: "Needs attention:")
  end

  test "reasons_popover's accessible name is scoped to the record when record_label is given" do
    html = reimbursements_reasons_popover(reasons: [ "No budget" ], key: "review-recExp1",
                                          label: "Needs attention", heading: "Needs attention:",
                                          record_label: "#123")

    assert_includes html, 'aria-label="Needs attention for #123"'
    # The visible text is unchanged: the scoping is for assistive tech.
    assert_match(%r{<button[^>]*>\s*Needs attention}, html)
  end

  # A disclosure region, not a menu: aria-haspopup would be an ARIA role mismatch.
  test "reasons_popover without record_label is named by its label and claims no menu popup" do
    html = reimbursements_reasons_popover(reasons: [ "No budget" ], key: "x",
                                          label: "Needs attention", heading: "Needs attention:")

    assert_includes html, 'aria-label="Needs attention"'
    assert_not_includes html, "aria-haspopup"
  end

  test "producer status badge shows the friendly label + a tooltip, not the raw status" do
    html = reimbursements_producer_status_badge("Submitted")
    assert_includes html, "Sent to EUSA"
    assert_not_includes html, ">Submitted<"
    assert_includes html, "title=\"Sent to the Students#{ERB::Util.html_escape("'")} Association (EUSA) for payment.\""
  end

  test "producer status badge keeps the status colour variant" do
    assert_includes reimbursements_producer_status_badge("Paid"), "text-success"
    assert_includes reimbursements_producer_status_badge("Rejected"), "text-danger"
  end

  test "producer status badge about someone else's claim keeps the word but not the second person" do
    html = reimbursements_producer_status_badge("Paid", own_claim: false)
    assert_match(/>\s*Paid\s*</, html)
    assert_includes html, 'title="EUSA has paid it."'
    assert_not_includes html, "your bank account"
    # A tooltip with nothing addressed to the submitter is shared as is.
    assert_includes reimbursements_producer_status_badge("Approved", own_claim: false),
                    "waiting to be sent to EUSA for payment."
  end

  test "producer status badge falls back to the raw status for an unknown value" do
    html = reimbursements_producer_status_badge("Weird")
    assert_includes html, "Weird"
  end

  # --- Who a producer writes to ------------------------------------------
  # CostCentre.default names an arbitrary pot once a second exists, so the wrong team
  # would be written to.

  test "the contact link names the cost centre of the claim it is shown beside" do
    termtime = create_second_reimbursements_cost_centre

    assert_includes reimbursements_contact_link(termtime), termtime.contact_email
    assert_not_includes reimbursements_contact_link(termtime), termtime.receive_mailbox
  end

  test "the contact link answers from the sole centre when a claim names none" do
    assert_includes reimbursements_contact_link, ::Reimbursements::CostCentre.sole_configured.contact_email
  end

  test "with a choice to make and no claim to ask, it says words rather than a wrong mailbox" do
    create_second_reimbursements_cost_centre

    assert_equal "the finance team", reimbursements_contact_link
  end

  test "email-in names every configured mailbox, since each files into its own pot" do
    create_second_reimbursements_cost_centre

    links = reimbursements_receive_mailbox_links

    assert_includes links, "in@bedlamtheatre.invalid"
    assert_includes links, ::Reimbursements::CostCentre.default.receive_mailbox
  end

  # An income line's `remaining` is nil even with a figure set, so the no-budget wording
  # would contradict the Initial column.
  test "an income line with a plan does not claim nobody set a budget" do
    income = create_reimbursements_budget(name: "Ticket income", budget_type: "Income",
                                          initial_budget: 800)

    rendered = reimbursements_budget_remaining(income)

    assert_nil income.remaining, "the fixture must reproduce the nil this guards"
    assert_not_includes rendered, "No budget set"
    assert_includes rendered, "Income is measured by what it raises"
  end
end
