class ProposalsMailer < ActionMailer::Base
  default from: 'Bedlam Theatre <no-reply@bedlamtheatre.co.uk>'

  def new_proposal(proposal, creator, team_member)
    @proposal = proposal
    @creator = creator

    @team_member = team_member
    @user = team_member.user
    mail(to: @user.email, subject: "Bedlam Theatre Proposals - #{proposal.show_title}")
  end
end
