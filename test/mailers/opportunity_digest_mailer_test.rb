require "test_helper"

class OpportunityDigestMailerTest < ActionMailer::TestCase
  test "digest is addressed to the reviewer and lists each opportunity in both parts" do
    user = users(:committee)
    opportunity = opportunities(:unapproved_opportunity)

    email = OpportunityDigestMailer.digest(user, [ opportunity ])

    assert_equal "Opportunities awaiting review", email.subject
    assert_equal [ user.email ], email.to
    [ email.html_part, email.text_part ].each do |part|
      assert_includes part.body.to_s, opportunity.title
      assert_includes part.body.to_s, opportunity.creator.full_name
    end
  end

  test "digest renders creator-less and on-behalf submissions" do
    attrs = { description: "D", expiry_date: 2.weeks.from_now, approved: false,
              submitter_name: "Casey External", submitter_email: "casey@example.com" }
    external = Opportunity.create!(title: "External pending", **attrs)
    on_behalf = Opportunity.create!(title: "On-behalf pending", creator_id: 1, **attrs)

    email = OpportunityDigestMailer.digest(users(:committee), [ external, on_behalf ])

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s
      assert_includes body, "External pending"
      assert_includes body, "on behalf of Casey External"
      assert_equal 2, body.scan("Casey External").size, "each row credits the submitter"
    end
  end
end
