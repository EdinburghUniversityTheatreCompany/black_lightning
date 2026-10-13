require "test_helper"

class OpportunityDigestJobTest < ActiveJob::TestCase
  test "does not send any emails when there are no pending opportunities" do
    Opportunity.awaiting_review.destroy_all

    assert_no_enqueued_jobs only: MailDeliveryJob do
      OpportunityDigestJob.perform_now
    end
  end

  test "sends an email to each opportunity reviewer when pending opportunities exist" do
    assert_includes Role.find_by(name: "Opportunity Reviewer")&.users, users(:committee),
           "Expected committee user to have Opportunity Reviewer role"

    assert_enqueued_jobs(1, only: MailDeliveryJob) do
      OpportunityDigestJob.perform_now
    end
  end
end
