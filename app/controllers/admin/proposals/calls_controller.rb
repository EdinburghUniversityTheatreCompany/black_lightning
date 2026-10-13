##
# Controller for Admin::Propsosals::Call. More details can be found there.
##

class Admin::Proposals::CallsController < AdminController
  include GenericController

  before_action :set_paper_trail_whodunnit
  load_and_authorize_resource

  ##
  # GET /admin/proposals/calls
  #
  # Dashboard of proposals awaiting approval or a GM outcome, across calls. Which proposals a
  # user sees is enforced by the :read rules in ability.rb.
  ##
  def index
    authorize! :index, Admin::Proposals::Proposal

    scoped = Admin::Proposals::Proposal
      .accessible_by(current_ability, :read)
      .includes(:call, team_members: :user)
      .references(:call)
      .merge(Admin::Proposals::Call.not_archived)
      .order("admin_proposals_calls.editing_deadline ASC")

    @awaiting_approval = scoped.awaiting_approval
    @approved = scoped.approved

    # Open calls with no proposals still get a New Proposal button.
    @open_calls = Admin::Proposals::Call.open.order(:editing_deadline)

    @title = "Proposals"
  end

  ##
  # PUT /admin/proposals/call/1/archive
  ##
  def archive
    if @call.archive
      flash[:success] = "The Proposal Call has been successfully archived."
    else
      flash[:error] = "Error archiving the Proposal Call. Has the editing deadline been reached?"
    end

    respond_to do |format|
      format.html { redirect_to admin_proposals_calls_path }
      # format.json { head :no_content }
    end
  end

  private

  def resource_class
    Admin::Proposals::Call
  end

  def permitted_params
    [
      :submission_deadline, :editing_deadline, :name, :archived,
      questions_attributes: [ :id, :_destroy, :question_text, :response_type ]
    ]
  end

  def new_title
    "New Proposal Call"
  end
end
