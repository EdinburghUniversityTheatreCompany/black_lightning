class ProposalsMailerTest < ActionMailer::TestCase
  def test_new_proposal
    call = FactoryGirl.create(:proposal_call)

    proposal = FactoryGirl.create(:proposal, call: call)
    user = proposal.users.first()

    # Send the email, then test that it got queued
    email = ProposalsMailer.new_proposal(proposal, user).deliver
    assert !ActionMailer::Base.deliveries.empty?

    # Test the body of the sent email contains what we expect it to
    assert_equal [user.email], email.to
    assert_equal "Bedlam Theatre Proposals - #{proposal.show_title}", email.subject
  end
end