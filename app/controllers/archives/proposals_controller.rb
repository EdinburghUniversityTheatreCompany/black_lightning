class Archives::ProposalsController < AdminController
  include GenericController

  def index
    @title = 'Proposal Archive'

    super
  end

  private

  # The next chapter in hacky solutions to accessible by errors.
  # Because accessible_by and the search both need the team_members table, it errors when you search for a person name.

  def proposal_search_result
    result_ids = base_index_ransack_query.ids

    # These are the proposals that are the result of the search.
    return Admin::Proposals::Proposal.where(id: result_ids).accessible_by(current_ability)
  end

  def load_index_resources
    result_proposals = proposal_search_result
    call_ids = result_proposals.collect(&:call_id).uniq

    @calls = Admin::Proposals::Call.where(id: call_ids)
                                   .reorder('submission_deadline DESC')
                                   .paginate(page: params[:page], per_page: 20)

    @proposals = result_proposals.where(call_id: @calls.ids)
                                 .includes(:call, team_members: [user: [:admin_maintenance_debts, :admin_staffing_debts]])
                                 .order('admin_proposals_calls.submission_deadline DESC')
                                 .group_by(&:call)

    return @proposals
  end

  def random_resources
    proposal_search_result
  end

  def resource_class
    Admin::Proposals::Proposal
  end
end
