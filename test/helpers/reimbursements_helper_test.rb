require "test_helper"

class ReimbursementsHelperTest < ActionView::TestCase
  Expense = ::Reimbursements::Expense
  Person = ::Reimbursements::Person
  Budget = ::Reimbursements::Budget
  ModulusCheck = ::Reimbursements::ModulusCheck

  class FixedChecker
    def initialize(result) = @result = result
    def check(_sort, _account) = @result
  end

  def expense_with(status)
    Expense.new(record_id: "recExp1", status: "Pending", ai_check_status: status)
  end

  def person_with(sort_code: "08-99-99", account_number: "66374958")
    Person.new(record_id: "recPer1", name: "Pat Producer", email: "pat@example.com",
              sort_code: sort_code, account_number: account_number)
  end

  test "modulus badge renders a warning 'Missing' badge for a payee with no bank details" do
    # Missing blocks approval like INVALID does, so it's a warning, not neutral.
    html = reimbursements_modulus_badge(person_with(sort_code: "", account_number: ""))
    assert_includes html, "Missing"
    assert_includes html, "text-warning"
  end

  test "modulus badge renders green Valid for a VALID result" do
    html = reimbursements_modulus_badge(person_with, checker: FixedChecker.new(ModulusCheck::VALID))
    assert_includes html, "Valid"
    assert_includes html, "text-success"
  end

  test "modulus badge renders red Invalid for an INVALID result" do
    html = reimbursements_modulus_badge(person_with, checker: FixedChecker.new(ModulusCheck::INVALID))
    assert_includes html, "Invalid"
    assert_includes html, "text-danger"
  end

  test "modulus badge renders amber Outside spec for an OUTSIDE_SPEC result" do
    html = reimbursements_modulus_badge(person_with, checker: FixedChecker.new(ModulusCheck::OUTSIDE_SPEC))
    assert_includes html, "Outside spec"
    assert_includes html, "text-warning"
  end

  test "effective modulus badge checks the expense's EFFECTIVE bank details, not the linked person's" do
    person = person_with(sort_code: "", account_number: "") # no bank details of their own
    expense = Expense.new(record_id: "recExp1", status: "Pending", person: person,
                          sort_code_override: "20-20-20", account_number_override: "50502366")

    html = reimbursements_effective_modulus_badge(expense, checker: FixedChecker.new(ModulusCheck::VALID))

    assert_includes html, "Valid", "the override bank details are present, so this must not fall back to Missing"
  end

  test "effective modulus badge falls back to Missing when there's no override and no linked person" do
    expense = Expense.new(record_id: "recExp1", status: "Pending", person: nil)

    html = reimbursements_effective_modulus_badge(expense)

    assert_includes html, "Missing"
  end

  test "access check badge maps ok/fail/skip to success/danger/secondary" do
    assert_includes reimbursements_access_check_badge(:ok), "OK"
    assert_includes reimbursements_access_check_badge(:ok), "text-success"
    assert_includes reimbursements_access_check_badge(:fail), "FAIL"
    assert_includes reimbursements_access_check_badge(:fail), "text-danger"
    assert_includes reimbursements_access_check_badge(:skip), "SKIP"
    assert_includes reimbursements_access_check_badge(:skip), "text-gray-700"
  end

  test "access check badge falls back to secondary for an unrecognised status" do
    html = reimbursements_access_check_badge(:weird)
    assert_includes html, "WEIRD"
    assert_includes html, "text-gray-700"
  end

  test "budget_owner_names comma-joins resolved owner names, skipping unknown ids" do
    people_by_id = { "recPer1" => person_with, "recPer2" => Person.new(record_id: "recPer2", name: "Alex",
                                                                       email: "alex@example.com") }
    budget = Budget.new(record_id: "recBud1", name: "Props", owner_ids: %w[recPer1 recPer2 recGone])

    assert_equal "Pat Producer, Alex", budget_owner_names(budget, people_by_id)
  end

  test "budget_owner_names returns an empty string when there are no owners" do
    budget = Budget.new(record_id: "recBud1", name: "Props", owner_ids: [])
    assert_equal "", budget_owner_names(budget, {})
  end

  test "AI badge maps pass to a green success badge" do
    html = reimbursements_ai_badge(expense_with("pass"))
    assert_includes html, "AI: Pass"
    assert_includes html, "text-success"
  end

  test "AI badge maps fail to a red danger badge" do
    html = reimbursements_ai_badge(expense_with("fail"))
    assert_includes html, "AI: Fail"
    assert_includes html, "text-danger"
  end

  test "AI badge maps error to an amber warning badge" do
    html = reimbursements_ai_badge(expense_with("error"))
    assert_includes html, "AI: Error"
    assert_includes html, "text-warning"
  end

  test "AI badge is case-insensitive" do
    html = reimbursements_ai_badge(expense_with("Pass"))
    assert_includes html, "text-success"
  end

  test "blank AI status renders a neutral secondary badge" do
    html = reimbursements_ai_badge(expense_with(""))
    assert_includes html, "text-gray-700"
    assert_includes html, "Unchecked"
  end

  test "reimbursements_date formats a Date as ISO 8601" do
    assert_equal "2026-07-11", reimbursements_date(Date.new(2026, 7, 11))
  end

  test "reimbursements_date takes the date part of a Time" do
    assert_equal "2026-07-11", reimbursements_date(Time.utc(2026, 7, 11, 9, 30))
  end

  test "reimbursements_date renders nil and blank as a dash" do
    assert_equal "-", reimbursements_date(nil)
    assert_equal "-", reimbursements_date("")
  end

  test "reimbursements_money formats a value as GBP with 2dp" do
    assert_equal "£12.50", reimbursements_money(12.5)
  end

  test "reimbursements_money renders zero as £0.00, not a dash" do
    assert_equal "£0.00", reimbursements_money(0)
  end

  test "reimbursements_money renders nil as a dash" do
    assert_equal "-", reimbursements_money(nil)
  end

  test "reimbursements_money accepts a pre-formatted numeric string (emails)" do
    assert_equal "£1,234.50", reimbursements_money("1234.50")
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
    # The visible label text still just reads "Needs attention" (the scoping
    # is for assistive tech, not a visible change).
    assert_match(%r{<button[^>]*>\s*Needs attention}, html)
  end

  test "reasons_popover falls back to the plain label without record_label" do
    html = reimbursements_reasons_popover(reasons: [ "No budget" ], key: "x",
                                          label: "Needs attention", heading: "Needs attention:")

    assert_includes html, 'aria-label="Needs attention"'
  end

  # The panel is a plain disclosure region (static text), not a menu — claiming
  # aria-haspopup="true" (equivalent to "menu") would be an ARIA role mismatch.
  test "reasons_popover trigger does not claim a menu popup type" do
    html = reimbursements_reasons_popover(reasons: [ "No budget" ], key: "x",
                                          label: "Needs attention", heading: "Needs attention:")

    assert_not_includes html, "aria-haspopup"
  end
end
