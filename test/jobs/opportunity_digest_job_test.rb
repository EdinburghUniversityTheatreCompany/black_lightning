require "test_helper"

class OpportunityDigestJobTest < ActiveJob::TestCase
  test "does not send any emails when there are no pending opportunities" do
    # Ensure no unapproved non-expired opportunities exist
    Opportunity.where(approved: false).where("expiry_date > ?", Date.current).destroy_all

    assert_no_enqueued_emails do
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

    assert_enqueued_emails(1) do
      OpportunityDigestJob.perform_now
    end

    enqueued = ActionMailer::Base.deliveries
    # With deliver_later in test mode (inline delivery), check enqueued jobs
    job_data = enqueued_jobs.last
    assert_not_nil job_data
  end

  test "sends one email per reviewer" do
    # Confirm there is exactly one reviewer
    reviewer_role = Role.find_by(name: "Opportunity Reviewer")
    reviewer_count = reviewer_role&.users&.count || 0

    assert opportunities(:unapproved_opportunity).expiry_date > Date.current

    assert_enqueued_emails(reviewer_count) do
      OpportunityDigestJob.perform_now
    end
  end
end
