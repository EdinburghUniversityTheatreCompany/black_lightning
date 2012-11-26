class ProposalsMailer < ActionMailer::Base
  default from: "proposals@bedlamtheatre.co.uk"

  def new_proposal(proposal, creator)
    @proposal = proposal
    @creator = creator

    proposal.team_members.each do |team_member|
      @team_member = team_member
      @user = team_member.user
      mail(:to => @user.email, :subject => "Bedlam Theatre Proposals - #{proposal.show_title}")
    end
  end
end
