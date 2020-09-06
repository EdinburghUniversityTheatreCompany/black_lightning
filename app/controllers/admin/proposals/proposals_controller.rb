##
# Controller for Admin::Proposals::Proposal. More details can be found there.
# ---
# *IMPORTANT*
#
# The proposal permissions are very carefully laid out in the ability.rb file.
# Please be very very very careful when editing them, or kittens may die.
##
class Admin::Proposals::ProposalsController < AdminController
  include GenericController

  before_action :set_paper_trail_whodunnit
  load_and_authorize_resource class: Admin::Proposals::Proposal

  ##
  # GET /admin/proposals/calls/1/proposals
  #
  # GET /admin/proposals/calls/1/proposals.json
  ##
  def index
    @call = Admin::Proposals::Call.find(params[:call_id])
    @title = "Proposals for #{@call.name}"

    super
  end

  ##
  # GET /admin/proposals/proposals/1
  #
  # GET /admin/proposals/proposals/1.json
  ##
  def show
    @call = @proposal.call

    @proposal.instantiate_answers!

    super
  end

  ##
  # GET /admin/proposals/proposals/new
  #
  # GET /admin/proposals/proposals/new.json
  # ---
  ##
  def new
    @call = Admin::Proposals::Call.find(params[:call_id])

    return call_closed_message unless @call.open?

    @proposal.call = @call

    @proposal.instantiate_answers!

    super
  end

  ##
  # POST /admin/proposals/proposals
  #
  # POST /admin/proposals/proposals.json
  ##
  def create
    @call = Admin::Proposals::Call.find(params[:call_id])

    return call_closed_message unless @call.open?

    @proposal.call = @call

    super

    #format.html { redirect_to admin_proposals_call_proposal_path(@call, @proposal), notice: 'Proposal was successfully created.' }
    #format.json { render json: @proposal, status: :created, location: admin_proposals_call_proposal_path(@call, proposal) }
  end

  ##
  # GET /admin/proposals/proposals/1/edit
  ##
  def edit
    @call = @proposal.call

    @proposal.instantiate_answers!

    super
  end

  ##
  # PUT /admin/proposals/proposals/1
  #
  # PUT /admin/proposals/proposals/1.json
  ##
  def update
    @call = @proposal.call

    @previous_team_member_ids = @proposal.team_member_ids

    super
  end

  ##
  # PUT /admin/proposals/proposals/1/approve
  #
  # PUT /admin/proposals/proposals/1/approve.json
  ##
  def approve
    @call = @proposal.call

    @proposal.approved = true
    @proposal.save!

    respond_to do |format|
      flash[:success] = "#{@proposal.show_title} has been marked as approved"

      format.html { redirect_to admin_proposals_call_proposal_path(@call, @proposal) }
      format.json { head :no_content }
    end
  end

  ##
  # PUT /admin/proposals/proposals/1/reject
  #
  # PUT /admin/proposals/proposals/1/reject.json
  ##
  def reject
    @call = @proposal.call

    @proposal.approved = false
    @proposal.save!

    respond_to do |format|
      flash[:success] = "#{@proposal.show_title} has been marked as rejected"

      format.html { redirect_to admin_proposals_call_proposal_path(@call, @proposal) }
      format.json { head :no_content }
    end
  end

  ##
  # PUT /admin/proposals/proposals/1/convert
  #
  # PUT /admin/proposals/proposals/1/convert.json
  ##
  def convert
    @proposal = Admin::Proposals::Proposal.find(params[:id])
    @call = @proposal.call

    begin
      @proposal.convert_to_show

      flash[:notice] = "#{@proposal.show_title} is queued to be converted. Please remember to check the automatically entered show info, enter the rest of the show info, and to publicise the show."
    rescue ArgumentError => e
      helpers.append_to_flash(:error, e.message)
    ensure
      respond_to do |format|
        format.html { redirect_to admin_proposals_call_proposal_path(@call, @proposal) }
        format.json { head :no_content }
      end
    end
  end

  def about
    # Renders a help page.
  end

  private

  def call_closed_message
    flash[:error] = "Sorry. The submission deadline for #{@call.name} has been passed and the call is no longer open. You can no longer submit a proposal for this call."
    redirect_to admin_proposals_call_proposals_path(@call)
    return
  end

  def mail_team_members(current_team_members, previous_team_member_ids, new)
    # Send the new proposal mail. See ProposalsMailer for more details.
    current_team_members.select { |team_member| previous_team_member_ids.exclude?(team_member.id) }.each do |team_member|
      ProposalsMailer.added_to_proposal(@proposal, current_user, team_member, new).deliver_later
    end
  end

  def permitted_params
    [
      :proposal_text, :publicity_text, :show_title, :late, :approved, :successful,
      answers_attributes: %I[id _destroy answer question_id file],
      team_members_attributes: %I[id _destroy position user user_id proposal proposal_id]
    ]
  end

  def index_query_params
    { call: @call }
  end

  def resource_class
    Admin::Proposals::Proposal
  end

  def on_create_success
    mail_team_members(@proposal.team_members, [], true)

    super
  end
  
  def on_update_success
    # Only email people if the proposal is edited before the editing deadline to prevent spamming people when tidying the archives.
    mail_team_members(@proposal.team_members, @previous_team_member_ids, false) if @proposal.call.editing_deadline > DateTime.now

    super
  end
end
