require "test_helper"

module Reimbursements
  class CredentialsCheckJobTest < ActiveSupport::TestCase
    teardown do
      ENV.delete("REIMBURSEMENTS_AZURE_SECRET_EXPIRES_ON")
      ENV.delete("REIMBURSEMENTS_ALERT_EMAIL")
    end

    test "does nothing when no expiry date is configured" do
      assert_no_emails { CredentialsCheckJob.perform_now }
    end

    test "does nothing when the secret expires far in the future" do
      ENV["REIMBURSEMENTS_AZURE_SECRET_EXPIRES_ON"] = 90.days.from_now.to_date.iso8601

      assert_no_emails { CredentialsCheckJob.perform_now }
    end

    test "warns the alert address inside the 30-day window" do
      ENV["REIMBURSEMENTS_AZURE_SECRET_EXPIRES_ON"] = 10.days.from_now.to_date.iso8601
      ENV["REIMBURSEMENTS_ALERT_EMAIL"] = "it-sub@example.com"

      assert_emails 1 do
        CredentialsCheckJob.perform_now
      end
      email = ActionMailer::Base.deliveries.last
      assert_equal [ "it-sub@example.com" ], email.to
      assert_match(/expires in 10 days/, email.subject)
    end

    test "falls back to the default IT address" do
      ENV["REIMBURSEMENTS_AZURE_SECRET_EXPIRES_ON"] = Date.current.iso8601

      assert_emails 1 do
        CredentialsCheckJob.perform_now
      end
      assert_equal [ ReimbursementsMailer::DEFAULT_ALERT_EMAIL ], ActionMailer::Base.deliveries.last.to
    end
  end
end
