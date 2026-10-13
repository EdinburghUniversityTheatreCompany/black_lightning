require "test_helper"

class OpportunityMailerTest < ActionMailer::TestCase
  test "expiry_reminder goes to the creator, names the posting by display title and links to edit" do
    # title is optional, so reading the raw column addressed the producer about opportunity "".
    opportunity = opportunities(:internal_project_opportunity)
    assert_nil opportunity.title

    email = OpportunityMailer.expiry_reminder(opportunity)

    assert_equal [ opportunity.creator.email ], email.to
    assert_includes email.subject, opportunity.display_title
    assert_includes email.text_part.body.to_s, opportunity.display_title
    html = email.html_part.body.to_s
    assert_includes html, opportunity.display_title
    assert_includes html, "/admin/opportunities/#{opportunity.id}/edit"
  end

  test "approved is sent to the creator with the display title in the subject" do
    opportunity = opportunities(:internal_project_opportunity)

    email = OpportunityMailer.approved(opportunity)

    assert_equal [ opportunity.creator.email ], email.to
    assert_includes email.subject, opportunity.display_title
    assert_includes email.subject, "approved"
  end

  test "approved goes to the account creator, not the external submitter, when both are present" do
    # Entered by the creator on the submitter's behalf, so the decision goes to the creator, not the
    # external person.
    opportunity = opportunities(:internal_project_opportunity)
    opportunity.update_columns(submitter_name: "Jane Director", submitter_email: "jane@example.com")

    email = OpportunityMailer.approved(opportunity)

    assert_equal [ opportunity.creator.email ], email.to
    assert_includes email.html_part.body.to_s, "Dear #{opportunity.creator.name}"
    assert_not_includes email.html_part.body.to_s, "Jane Director"
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

  test "rejected is sent to the submitter with the display title in the subject" do
    opportunity = opportunities(:external_project_opportunity)

    email = OpportunityMailer.rejected(opportunity, "Not quite right for us.")

    assert_equal [ "jane@example.com" ], email.to
    assert_includes email.subject, "not approved"
    assert_includes email.html_part.body.to_s, "Not quite right for us."
  end
end
