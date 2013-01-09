##
# Controller for Admin::Proposals::Proposal. More details can be found there.
# ---
# *IMPORTANT*
#
# Due to the complex nature of proposal permissions, each action may need to be authorized
# in the controller method using the authorize! method.
#
# Failure to correctly do so will cause bad things to happen (kittens may die).
##
class Admin::Proposals::ProposalsController < AdminController

  authorize_resource :class => "Admin::Proposals::Proposal"

  ##
  # GET /admin/proposals/proposals
  #
  # GET /admin/proposals/proposals.json
  ##
  def index
    @call = Admin::Proposals::Call.find(params[:call_id])

    if Time.now < @call.deadline
      # Before the deadline, all users can only see proposals that they
      # are part of.
      @proposals = @call.proposals.joins(:users).where("user_id = ?", current_user.id).uniq
    elsif not @call.archived
      # After the deadline:
      if current_user.has_role? :committee
        # Committee can see all proposals.
        @proposals = @call.proposals
      else
        # Other users can only see proposals that they are part of, or
        # that have been approved.
        @proposals = @call.proposals.joins(:users).where("user_id = ? or approved = true", current_user.id).uniq
      end
    else
      # for archived calls, only approved proposals may be seen:
      @proposals = @call.proposals.where("approved = true").uniq
    end

    # However, admin can see all proposals at any time.
    if current_user.has_role? :admin
      @proposals = @call.proposals
    end

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @admin_proposals_proposals }
    end
  end

  ##
  # GET /admin/proposals/proposals/1
  #
  # GET /admin/proposals/proposals/1.json
  ##
  def show
    @admin_proposals_proposal = Admin::Proposals::Proposal.find(params[:id])
    @call = @admin_proposals_proposal.call

    authorize!(:read, @admin_proposals_proposal)

    @admin_proposals_proposal.update_answers
    @admin_proposals_proposal.save

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @admin_proposals_proposal }
    end
  end

  ##
  # GET /admin/proposals/proposals/new
  #
  # GET /admin/proposals/proposals/new.json
  # ---
  # Note that proposals created after the call's deadline will be marked as late here.
  #
  # It is also important that an Admin::Answer for each Admin::Question is created here.
  ##
  def new
    @call = Admin::Proposals::Call.find(params[:call_id])

    if not @call.open then
      flash[:alert] = "Sorry. #{@call.name} isn't open yet. You cannot add a proposal for a closed call."
      redirect_to admin_proposals_calls_path
      return
    end

    @proposal = Admin::Proposals::Proposal.new
    @users = User.by_first_name.all

    @proposal.call = @call

    #Set a proposal as late if created after the call deadline:
    if Time.now > @call.deadline then
      @proposal.late = true
    end

    @proposal.update_answers

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @proposal }
    end
  end

  ##
  # GET /admin/proposals/proposals/1/edit
  # ---
  # Don't forget to re-read the call's Admin::Question s from here. Questions may have been created, so will need Admin::Answer s
  ##
  def edit
    @proposal = Admin::Proposals::Proposal.find(params[:id])
    @call = @proposal.call
    @users = User.by_first_name.all

    authorize!(:edit, @proposal)

    @proposal.update_answers
    @proposal.save
  end

  ##
  # POST /admin/proposals/proposals
  #
  # POST /admin/proposals/proposals.json
  ##
  def create
    @call = Admin::Proposals::Call.find(params[:call_id])

    if not @call.open then
      flash[:alert] = "Sorry. #{@call.name} isn't open yet. You cannot add a proposal for a closed call."
      redirect_to admin_proposals_calls_path
      return
    end

    @proposal = Admin::Proposals::Proposal.new(params[:admin_proposals_proposal])

    @proposal.call = @call

    #This is required so that the new action can be rendered should the save fail.
    @users = User.by_first_name.all

    #Set a proposal as late if created after the call deadline:
    if Time.now > @call.deadline then
      @proposal.late = true
    end

    respond_to do |format|
      if @proposal.save
        #Send the new proposal mail. See ProposalsMailer for more details.

        @proposal.team_members.each do |team_member|
          dj = ProposalsMailer.delay.new_proposal(@proposal, current_user, team_member)
          dj.description = "Proposal Mailer - #{@proposal.show_title} - #{team_member.user.name}"
          dj.save
        end

        format.html { redirect_to admin_proposals_call_proposal_path(@call, @proposal), notice: 'Proposal was successfully created.' }
        format.json { render json: @proposal, status: :created, location: admin_proposals_call_proposal_path(@call, proposal) }
      else
        format.html { render "new" }
        format.json { render json: @proposal.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # PUT /admin/proposals/proposals/1
  #
  # PUT /admin/proposals/proposals/1.json
  ##
  def update
    @proposal = Admin::Proposals::Proposal.find(params[:id])
    @call = @proposal.call

    #This is required so that the edit action can be rendered should the update fail.
    @users = User.by_first_name.all

    authorize!(:edit, @proposal)

    respond_to do |format|
      if @proposal.update_attributes(params[:admin_proposals_proposal])
        format.html { redirect_to admin_proposals_call_proposal_path(@call, @proposal), notice: 'Proposal was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render "edit" }
        format.json { render json: @proposal.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/proposals/proposals/1
  #
  # DELETE /admin/proposals/proposals/1.json
  ##
  def destroy
    @admin_proposals_proposal = Admin::Proposals::Proposal.find(params[:id])

    authorize!(:destory, @proposal)

    @admin_proposals_proposal.destroy

    respond_to do |format|
      format.html { redirect_to admin_proposals_call_proposals_url }
      format.json { head :no_content }
    end
  end

  ##
  # PUT /admin/proposals/proposals/1/approve
  #
  # PUT /admin/proposals/proposals/1/approve.json
  ##
  def approve
    @proposal = Admin::Proposals::Proposal.find(params[:id])
    @call = @proposal.call

    authorize!(:approve, @proposal)

    @proposal.approved = true
    @proposal.save!

    respond_to do |format|
      flash[:success] = "#{@proposal.show_title} has been marked as approved"
      format.html { redirect_to admin_proposals_call_proposals_path(@call)}
      format.json { head :no_content }
    end
  end

  ##
  # PUT /admin/proposals/proposals/1/reject
  #
  # PUT /admin/proposals/proposals/1/reject.json
  ##
  def reject
    @proposal = Admin::Proposals::Proposal.find(params[:id])
    @call = @proposal.call

    authorize!(:reject, @proposal)

    @proposal.approved = false
    @proposal.save!

    respond_to do |format|
      flash[:success] = "#{@proposal.show_title} has been marked as rejected"
      format.html { redirect_to admin_proposals_call_proposals_path(@call)}
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

    @proposal.convert_to_show

    respond_to do |format|
      flash[:notice] = "#{@proposal.show_title} is queued to be converted."
      format.html { redirect_to admin_proposals_call_proposals_path(@call)}
      format.json { head :no_content }
    end
  end

  def about
  end
end
