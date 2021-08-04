class ProposalsMailer < ApplicationMailer
  def added_to_proposal(proposal, updater, team_member, new)
    @proposal = proposal
    @updater = updater

    @team_member = team_member
    @user = team_member.user

    @new = new
    
    @subject = "Bedlam Theatre Proposals - #{proposal.show_title}"

    mail(to: @user.email, subject: @subject)
  end
end
