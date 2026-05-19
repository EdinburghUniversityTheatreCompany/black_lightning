require "test_helper"

class OpportunityMailerTest < ActionMailer::TestCase
  test "expiry_reminder has correct subject" do
    opportunity = opportunities(:expiring_soon_opportunity)

    email = OpportunityMailer.expiry_reminder(opportunity)

    assert_includes email.subject, opportunity.title
  end

  test "expiry_reminder is sent to the creator" do
    opportunity = opportunities(:expiring_soon_opportunity)

    email = OpportunityMailer.expiry_reminder(opportunity)

    assert_equal [ opportunity.creator.email ], email.to
  end

  test "expiry_reminder HTML body includes opportunity title" do
    opportunity = opportunities(:expiring_soon_opportunity)

    email = OpportunityMailer.expiry_reminder(opportunity)
    html_body = email.html_part.body.to_s

    assert_includes html_body, opportunity.title
  end

  test "expiry_reminder text body includes opportunity title" do
    opportunity = opportunities(:expiring_soon_opportunity)

    email = OpportunityMailer.expiry_reminder(opportunity)
    text_body = email.text_part.body.to_s

    assert_includes text_body, opportunity.title
  end

  test "expiry_reminder HTML body includes edit link" do
    opportunity = opportunities(:expiring_soon_opportunity)

    email = OpportunityMailer.expiry_reminder(opportunity)
    html_body = email.html_part.body.to_s

    assert_includes html_body, "/admin/opportunities/#{opportunity.id}/edit"
  end
end
