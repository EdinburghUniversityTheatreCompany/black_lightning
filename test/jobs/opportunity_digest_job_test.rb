require "test_helper"

class OpportunityDigestJobTest < ActiveJob::TestCase
  test "does not send any emails when there are no pending opportunities" do
    # Ensure no unapproved non-expired opportunities exist
    Opportunity.where(approved: false).where("expiry_date > ?", Date.current).destroy_all

    assert_no_enqueued_jobs only: MailDeliveryJob do
      OpportunityDigestJob.perform_now
    end
  end

  test "sends an email to each opportunity reviewer when pending opportunities exist" do
    # unapproved_opportunity fixture is unapproved and expires in the future
    assert opportunities(:unapproved_opportunity).expiry_date > Date.current
    assert_not opportunities(:unapproved_opportunity).approved

    # committee fixture has the opportunity_reviewer role via users_roles fixture
    reviewer = users(:committee)
    assert Role.find_by(name: "Opportunity Reviewer")&.users&.include?(reviewer),
           "Expected committee user to have Opportunity Reviewer role"

    assert_enqueued_jobs(1, only: MailDeliveryJob) do
      OpportunityDigestJob.perform_now
    end
  end

  test "sends one email per reviewer" do
    # Confirm there is exactly one reviewer
    reviewer_role = Role.find_by(name: "Opportunity Reviewer")
    reviewer_count = reviewer_role&.users&.count || 0

    assert opportunities(:unapproved_opportunity).expiry_date > Date.current

    assert_enqueued_jobs(reviewer_count, only: MailDeliveryJob) do
      OpportunityDigestJob.perform_now
    end
  end

  test "renders the digest for external (creator-less) pending submissions without error" do
    Opportunity.create!(
      title: "External pending opportunity",
      description: "External pending submission for the digest.",
      expiry_date: 2.weeks.from_now,
      approved: false,
      submitter_name: "Casey External",
      submitter_email: "casey@example.com"
    )

    # perform_enqueued_jobs actually renders the digest, so a nil-creator row would raise here.
    perform_enqueued_jobs do
      OpportunityDigestJob.perform_now
    end

    assert ActionMailer::Base.deliveries.any?, "Expected the reviewer digest to be delivered"
  end
end
