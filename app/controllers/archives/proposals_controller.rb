class Archives::ProposalsController < ArchivesController
  before_filter :authenticate_user!

  def index
    @proposals = ::Admin::Proposals::Proposal.joins(:call).where( :admin_proposals_calls => { :deadline => @search_start_date..@search_end_date, :archived => true } ).group_by { |p| p.call }
  end
end