class ProposalsMailerTest < ActionMailer::TestCase
  def test_new_proposal
    user = users(:member)
    proposal = admin_proposals_proposals(:one)
    proposal.team_members = [::TeamMember.new({ :user => user, :position => 'Tester' })]
    proposal.save

    # Send the email, then test that it got queued
    email = ProposalsMailer.new_proposal(proposal, user).deliver
    assert !ActionMailer::Base.deliveries.empty?

    # Test the body of the sent email contains what we expect it to
    assert_equal [user.email], email.to
    assert_equal "Bedlam Theatre Proposals - #{proposal.show_title}", email.subject
  end
end