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

  # --- approved -------------------------------------------------------------

  test "approved is sent to the creator with the display title in the subject" do
    opportunity = opportunities(:internal_project_opportunity)

    email = OpportunityMailer.approved(opportunity)

    assert_equal [ opportunity.creator.email ], email.to
    assert_includes email.subject, opportunity.display_title
    assert_includes email.subject, "approved"
  end

  test "approved is sent to an external submitter's email" do
    opportunity = opportunities(:external_project_opportunity)

    email = OpportunityMailer.approved(opportunity)

    assert_equal [ "jane@example.com" ], email.to
  end

  test "approved goes to the external submitter, not the account creator, when both are present" do
    # A posting with both an account creator and an external submitter was created on the
    # submitter's behalf (see Opportunity#on_behalf_of?). The decision email is sent to the
    # external person (notification_email), so the salutation must name them too — otherwise we
    # address the wrong person in their own inbox.
    opportunity = opportunities(:internal_project_opportunity)
    opportunity.update_columns(submitter_name: "Jane Director", submitter_email: "jane@example.com")

    email = OpportunityMailer.approved(opportunity)

    assert_equal [ "jane@example.com" ], email.to
    assert_includes email.html_part.body.to_s, "Dear Jane Director"
    assert_not_includes email.html_part.body.to_s, opportunity.creator.name
  end

  test "approved includes the reviewer note when given" do
    opportunity = opportunities(:external_project_opportunity)

    email = OpportunityMailer.approved(opportunity, "Looks great, thanks!")

    assert_includes email.html_part.body.to_s, "Looks great, thanks!"
    assert_includes email.text_part.body.to_s, "Looks great, thanks!"
  end

  test "approved omits the note section when blank" do
    opportunity = opportunities(:external_project_opportunity)

    email = OpportunityMailer.approved(opportunity, "")

    assert_not_includes email.html_part.body.to_s, "A note from the reviewer"
  end

  # --- rejected -------------------------------------------------------------

  test "rejected is sent to the submitter with the display title in the subject" do
    opportunity = opportunities(:external_project_opportunity)

    email = OpportunityMailer.rejected(opportunity, "Not quite right for us.")

    assert_equal [ "jane@example.com" ], email.to
    assert_includes email.subject, "not approved"
    assert_includes email.html_part.body.to_s, "Not quite right for us."
  end
end
