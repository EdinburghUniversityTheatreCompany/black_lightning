class Archives::ProposalsController < AdminController
  def index
    authorize! :index, Admin::Proposals::Proposal

    @title = 'Proposal Archive'

    @q = Admin::Proposals::Proposal.ransack(params[:q])
    @proposals = @q.result(distinct: true).accessible_by(current_ability)
    @calls = Admin::Proposals::Call.where(id: @proposals.reverse.collect(&:call_id)).paginate(page: params[:page], per_page: 20)
    @proposals = @proposals.where(call_id: @calls.collect(&:id)).includes(:call, :team_members, :users).group_by(&:call)
  end
end
