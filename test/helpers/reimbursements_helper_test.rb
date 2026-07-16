require "test_helper"

class ReimbursementsHelperTest < ActionView::TestCase
  Expense = ::Reimbursements::Expense

  def expense_with(status)
    Expense.new(record_id: "recExp1", status: "Pending", ai_check_status: status)
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
