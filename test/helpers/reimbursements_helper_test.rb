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
end
