require "test_helper"

class ProposalsMailerTest < ActionMailer::TestCase
  test "should send added_to_proposal for new" do
    proposal = FactoryBot.create(:proposal)
    updater = proposal.users.first

    assert_difference "ActionMailer::Base.deliveries.count", proposal.team_members.count do
      # Send the email, then test that it got queued
      proposal.team_members.each do |team_member|
        email = ProposalsMailer.added_to_proposal(proposal, updater, team_member, true).deliver_now

        # Test the body of the sent email contains what we expect it to
        assert_equal [ team_member.user.email ], email.to
        assert_equal "Added to Bedlam Theatre Proposal - #{proposal.show_title}", email.subject

        assert_match "The proposal was submitted by #{updater.name}", email.text_part.to_s
        assert_match "The proposal was submitted by #{updater.name}", email.html_part.to_s
      end
    end
  end

  test "should send added_to_proposal for update" do
    # Mainly test if the line changes properly.

    proposal = FactoryBot.create(:proposal)
    updater = proposal.users.first

    team_member = proposal.team_members.first

    email = ProposalsMailer.added_to_proposal(proposal, updater, team_member, false).deliver_now

    assert_match "You have been added by #{updater.name}", email.text_part.to_s
    assert_match "You have been added by #{updater.name}", email.html_part.to_s
  end
end
