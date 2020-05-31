class Archives::ProposalsController < AdminController
  def index
    authorize! :index, Admin::Proposals::Proposal

    @title = 'Proposal Archive'
    @q = Admin::Proposals::Proposal.ransack(params[:q])
    @proposals = @q.result(distinct: true).accessible_by(current_ability).reverse.group_by(&:call)
  end
end