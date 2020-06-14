class ProposalsMailer < ActionMailer::Base
  default from: 'Bedlam Theatre <no-reply@bedlamtheatre.co.uk>'

  def added_to_proposal(proposal, updater, team_member, new)
    @proposal = proposal
    @updater = updater

    @team_member = team_member
    @user = team_member.user

    @new = new
    
    mail(to: @user.email, subject: "Bedlam Theatre Proposals - #{proposal.show_title}")
  end
end
