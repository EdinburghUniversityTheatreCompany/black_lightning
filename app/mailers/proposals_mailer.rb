class ProposalsMailer < ApplicationMailer
  def added_to_proposal(proposal, updater, team_member, new)
    @proposal = proposal
    @updater = updater

    @team_member = team_member
    @user = team_member.user

    @new = new

    @subject = "Added to Bedlam Theatre Proposal - #{proposal.show_title}"

    mail(to: email_address_with_name(@user.email, @user.full_name), subject: @subject)
  end
end
