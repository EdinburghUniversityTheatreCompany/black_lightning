require 'test_helper'

class ProposalsMailerTest < ActionMailer::TestCase
  test 'should send new_proposal' do
    call = FactoryGirl.create(:proposal_call)

    proposal = FactoryGirl.create(:proposal, call: call)
    creator = proposal.users.first

    # Send the email, then test that it got queued
    proposal.team_members.each do |team_member|
      email = ProposalsMailer.new_proposal(proposal, creator, team_member).deliver_now
      assert !ActionMailer::Base.deliveries.empty?

      # Test the body of the sent email contains what we expect it to
      assert_equal [team_member.user.email], email.to
      assert_equal "Bedlam Theatre Proposals - #{proposal.show_title}", email.subject
    end
  end
end
