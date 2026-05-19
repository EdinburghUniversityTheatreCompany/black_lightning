require "test_helper"

class OpportunityDigestMailerTest < ActionMailer::TestCase
  # Uses pending_digest_opportunity fixture which has creator_id: 1 (admin user with explicit id)

  test "digest has correct subject" do
    user = users(:committee)
    opportunity = opportunities(:pending_digest_opportunity)

    email = OpportunityDigestMailer.digest(user, [ opportunity ])

    assert_equal "Opportunities awaiting review", email.subject
  end

  test "digest is sent to the given user" do
    user = users(:committee)
    opportunity = opportunities(:pending_digest_opportunity)

    email = OpportunityDigestMailer.digest(user, [ opportunity ])

    assert_equal [ user.email ], email.to
  end

  test "digest HTML body includes opportunity title" do
    user = users(:committee)
    opportunity = opportunities(:pending_digest_opportunity)

    email = OpportunityDigestMailer.digest(user, [ opportunity ])
    html_body = email.html_part.body.to_s

    assert_includes html_body, opportunity.title
  end

  test "digest text body includes opportunity title" do
    user = users(:committee)
    opportunity = opportunities(:pending_digest_opportunity)

    email = OpportunityDigestMailer.digest(user, [ opportunity ])
    text_body = email.text_part.body.to_s

    assert_includes text_body, opportunity.title
  end

  test "digest includes submitter name" do
    user = users(:committee)
    opportunity = opportunities(:pending_digest_opportunity)

    email = OpportunityDigestMailer.digest(user, [ opportunity ])
    html_body = email.html_part.body.to_s

    assert_includes html_body, opportunity.creator.full_name
  end

  test "digest renders correctly for multiple opportunities" do
    user = users(:committee)
    opportunity = opportunities(:pending_digest_opportunity)

    # Pass the same opportunity twice to verify the loop renders multiple rows
    email = OpportunityDigestMailer.digest(user, [ opportunity, opportunity ])
    html_body = email.html_part.body.to_s

    assert html_body.scan(opportunity.title).count >= 2
  end
end
