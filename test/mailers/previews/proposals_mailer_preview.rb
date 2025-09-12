class ProposalsMailerPreview < ActionMailer::Preview
  def added_to_proposal
    proposal = Admin::Proposals::Proposal.all.sample || FactoryBot.create(:proposal)
    updater = proposal.users.sample || User.all.sample
    team_member = proposal.team_members.sample || TeamMember.all.sample
    new = [ true, false ].sample

    ProposalsMailer.added_to_proposal(proposal, updater, team_member, new)
  end
end
