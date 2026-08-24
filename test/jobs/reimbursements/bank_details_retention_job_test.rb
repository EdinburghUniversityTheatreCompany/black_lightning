require "test_helper"

module Reimbursements
  class BankDetailsRetentionJobTest < ActiveJob::TestCase
    include ReimbursementsTestHelpers

    def dormant_payee
      person = create_reimbursements_person(name: "Dormant Dora", email: "dora@example.com",
                                            sort_code: "08-99-99", account_number: "66374958")
      person.payment_details.update_columns(created_at: 8.months.ago, updated_at: 8.months.ago)
      person
    end

    test "clears a dormant payee's details and reports how many" do
      person = dormant_payee

      assert_equal 1, BankDetailsRetentionJob.perform_now
      assert_equal "", person.reload.account_number
    end

    test "is a no-op on a night with nothing to clear" do
      create_reimbursements_person(name: "Active Alex", email: "alex@example.com",
                                   sort_code: "08-99-99", account_number: "66374958")

      assert_equal 0, BankDetailsRetentionJob.perform_now
    end

    # A retention sweep that exists but is never scheduled does nothing at all,
    # and nothing else would notice: the job is silent by design, so its absence
    # from the schedule looks exactly like a quiet night.
    test "is scheduled to run nightly" do
      schedule = YAML.load_file(Rails.root.join("config/recurring.yml"))
      entry = schedule.fetch("reimbursements_bank_details_retention")

      assert_equal "Reimbursements::BankDetailsRetentionJob", entry["class"]
      assert_match(/every day/, entry["schedule"])
    end
  end
end
