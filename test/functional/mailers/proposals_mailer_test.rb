require 'test_helper'

class ProposalsMailerTest < ActionMailer::TestCase
  test 'should send new_proposal' do
    call = FactoryBot.create(:proposal_call)

    proposal = FactoryBot.create(:proposal, call: call)
    creator = proposal.users.first

    assert_difference 'ActionMailer::Base.deliveries.count', proposal.team_members.count do
      # Send the email, then test that it got queued
      proposal.team_members.each do |team_member|
        email = ProposalsMailer.new_proposal(proposal, creator, team_member).deliver_now

        # Test the body of the sent email contains what we expect it to
        assert_equal [team_member.user.email], email.to
        assert_equal "Bedlam Theatre Proposals - #{proposal.show_title}", email.subject
      end
    end
  end
end
