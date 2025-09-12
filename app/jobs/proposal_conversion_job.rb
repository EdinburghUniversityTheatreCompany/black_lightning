class ProposalConversionJob < ApplicationJob
  queue_as :default

  def perform(proposal_id)
    proposal = Admin::Proposals::Proposal.find(proposal_id)
    proposal.convert_to_show
  end
end
