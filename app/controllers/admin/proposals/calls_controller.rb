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
  # Cross-call dashboard of proposals still needing a decision. Shows:
  # - awaiting_approval proposals (with inline approve/reject for approvers)
  # - approved proposals (with inline mark_successful/mark_unsuccessful for approvers)
  #
  # Any logged-in user may open the page; per-proposal visibility is enforced by the existing
  # :read rules in ability.rb (team members see their own pre-deadline proposals; everyone sees
  # approved/successful/unsuccessful ones; proposal checkers see everything post-submission deadline).
  ##
  def index
    authorize! :index, Admin::Proposals::Proposal

    scoped = Admin::Proposals::Proposal
      .accessible_by(current_ability, :read)
      .includes(:call, team_members: :user)
      .references(:call)
      .where(admin_proposals_calls: { archived: [ false, nil ] })
      .order("admin_proposals_calls.editing_deadline ASC")

    @awaiting_approval = scoped.where(status: :awaiting_approval)
    @approved = scoped.where(status: :approved)

    # Surface every open call so the view can show a "New Proposal" CTA even for calls with no proposals yet.
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

  def index_query_params
    { archived: [ nil, false ] }
  end

  def new_title
    "New Proposal Call"
  end
end
