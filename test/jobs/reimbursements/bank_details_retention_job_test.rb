require "test_helper"

module Reimbursements
  class BankDetailsRetentionJobTest < ActiveJob::TestCase
    include ReimbursementsTestHelpers

    test "clears a dormant payee's details and reports how many" do
      person = create_reimbursements_person(name: "Dormant Dora", email: "dora@example.com",
                                            sort_code: "08-99-99", account_number: "66374958")
      person.payment_details.update_columns(created_at: 8.months.ago, updated_at: 8.months.ago)

      assert_equal 1, BankDetailsRetentionJob.perform_now
      assert_equal "", person.reload.account_number
    end
  end
end
