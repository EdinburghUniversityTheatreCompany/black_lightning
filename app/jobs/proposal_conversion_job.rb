class ProposalConversionJob < ApplicationJob
  queue_as :proposals

  def perform(proposal_id)
    proposal = Admin::Proposals::Proposal.find(proposal_id)
    Honeybadger.context(proposal_id: proposal.id, show_title: proposal.show_title)

    proposal.convert_to_show
  end
end
