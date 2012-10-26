class Admin::Proposals::ProposalsController < AdminController
  # GET /admin/proposals/proposals
  # GET /admin/proposals/proposals.json
  def index
    @call = Admin::Proposals::Call.find(params[:call_id])
    @proposals = @call.proposals

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @admin_proposals_proposals }
    end
  end

  # GET /admin/proposals/proposals/1
  # GET /admin/proposals/proposals/1.json
  def show
    @admin_proposals_proposal = Admin::Proposals::Proposal.find(params[:id])
    @call = @admin_proposals_proposal.call

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @admin_proposals_proposal }
    end
  end

  # GET /admin/proposals/proposals/new
  # GET /admin/proposals/proposals/new.json
  def new
    @call = Admin::Proposals::Call.find(params[:call_id])
    @proposal = Admin::Proposals::Proposal.new
    @users = User.all
    
    @proposal.call = @call

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @proposal }
    end
  end

  # GET /admin/proposals/proposals/1/edit
  def edit
    @proposal = Admin::Proposals::Proposal.find(params[:id])
    @call = @proposal.call
    @users = User.all
  end

  # POST /admin/proposals/proposals
  # POST /admin/proposals/proposals.json
  def create
    @call = Admin::Proposals::Call.find(params[:call_id])
    @proposal = Admin::Proposals::Proposal.new(params[:admin_proposals_proposal])
    
    @proposal.call = @call

    respond_to do |format|
      if @proposal.save
        format.html { redirect_to admin_proposals_call_proposal_path(@call, @proposal), notice: 'Proposal was successfully created.' }
        format.json { render json: @proposal, status: :created, location: admin_proposals_call_proposal_path(@call, proposal) }
      else
        format.html { render action: "new" }
        format.json { render json: @proposal.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /admin/proposals/proposals/1
  # PUT /admin/proposals/proposals/1.json
  def update
    @admin_proposals_proposal = Admin::Proposals::Proposal.find(params[:id])

    respond_to do |format|
      if @admin_proposals_proposal.update_attributes(params[:admin_proposals_proposal])
        format.html { redirect_to @admin_proposals_proposal, notice: 'Proposal was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @admin_proposals_proposal.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /admin/proposals/proposals/1
  # DELETE /admin/proposals/proposals/1.json
  def destroy
    @admin_proposals_proposal = Admin::Proposals::Proposal.find(params[:id])
    @admin_proposals_proposal.destroy

    respond_to do |format|
      format.html { redirect_to admin_proposals_call_proposals_url }
      format.json { head :no_content }
    end
  end
end
