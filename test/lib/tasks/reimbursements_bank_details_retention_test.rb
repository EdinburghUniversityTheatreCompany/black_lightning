require "test_helper"

class ReimbursementsBankDetailsRetentionTaskTest < ActiveSupport::TestCase
  include ReimbursementsTestHelpers
  include RakeTaskTestHelpers

  def dormant_payee
    person = create_reimbursements_person(name: "Dormant Dora", email: "dora@example.com",
                                          sort_code: "08-99-99", account_number: "66374958")
    person.payment_details.update_columns(created_at: 8.months.ago, updated_at: 8.months.ago)
    person
  end

  test "names the payees who would be cleared and changes nothing" do
    person = dormant_payee

    output = run_rake_task("reimbursements:bank_details_retention_preview")

    assert_match(/1 payee\(s\) would have their bank details cleared/, output)
    assert_match(/Dormant Dora/, output)
    assert_equal "66374958", person.reload.account_number, "a preview must not clear anything"
  end

  # A preview is for pasting into a chat with the committee, so it must not be
  # the one place the full number turns up.
  test "the preview never prints an account number" do
    dormant_payee

    output = run_rake_task("reimbursements:bank_details_retention_preview")

    assert_no_match(/66374958/, output)
  end

  test "says so plainly when there is nothing to clear" do
    create_reimbursements_person(name: "Active Alex", email: "alex@example.com",
                                 sort_code: "08-99-99", account_number: "66374958")

    output = run_rake_task("reimbursements:bank_details_retention_preview")

    assert_match(/Nothing would be cleared/, output)
  end
end
