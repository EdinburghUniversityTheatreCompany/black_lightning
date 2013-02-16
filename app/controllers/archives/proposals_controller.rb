class Archives::ProposalsController < ArchivesController
  before_filter :authenticate_user!

  def index
    @proposals = ::Admin::Proposals::Proposal.joins(:call).where({ :admin_proposals_calls => { :archived => true }, :approved => true })

    if @search_start_date && @search_end_date
      @proposals = @proposals.where({ :admin_proposals_calls => { :deadline => @search_start_date..@search_end_date } })
    end

    if @search_name
      @proposals = @proposals.where({ :show_title => @search_name })
    end

    @proposals = @proposals.group_by { |p| p.call }
  end
end