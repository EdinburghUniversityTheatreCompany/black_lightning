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
  # GET /admin/proposals/calls.json
  ##
  def index
    @title = "Proposals to the EUTC"

    super
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
