class Admin::Proposals::ProposalsController < AdminController

  authorize_resource :class => "Admin::Proposals::Proposal"

  # IMPORTANT
  # Due to the complex nature of proposal permissions, each action may need to be authorized
  # in the controller method using the authorize! method.
  # Failure to correctly do so will cause bad things to happen (kittens may die).

  # GET /admin/proposals/proposals
  # GET /admin/proposals/proposals.json
  def index
    @call = Admin::Proposals::Call.find(params[:call_id])
    @proposals = Admin::Proposals::Proposal.where(:call_id => @call.id)
    
    if not ((current_user.has_role? :committee) || (current_user.has_role? :admin)) then
      @proposals = @proposals.joins(:users).where('approved = true or user_id = ?', current_user.id)
    end

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
    
    authorize!(:read, @admin_proposals_proposal)

    @call.questions.each do |question|
      if not @admin_proposals_proposal.questions.all.include? question then
        answer = Admin::Proposals::Answer.new
        answer.question = question
        @admin_proposals_proposal.answers.push(answer)
      end
    end
    @admin_proposals_proposal.save
    
    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @admin_proposals_proposal }
    end
  end

  # GET /admin/proposals/proposals/new
  # GET /admin/proposals/proposals/new.json
  def new
    @call = Admin::Proposals::Call.find(params[:call_id])
    
    if not @call.open then
      flash[:alert] = "Sorry. #{@call.name} isn't open yet. You cannot add a proposal for a closed call."
      redirect_to admin_proposals_calls_path
      return
    end
    
    @proposal = Admin::Proposals::Proposal.new
    @users = User.all
    
    @proposal.call = @call
    
    #Set a proposal as late if created after the call deadline:
    if Time.now > @call.deadline then
      @proposal.late = true
    end
    
    @call.questions.each do |question|
      answer = Admin::Proposals::Answer.new
      answer.question = question
      @proposal.answers.push(answer)
    end

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
    
    authorize!(:edit, @proposal)
    
    @call.questions.each do |question|
      if not @proposal.questions.all.include? question then
        answer = Admin::Proposals::Answer.new
        answer.question = question
        @proposal.answers.push(answer)
      end
    end
    @proposal.save
  end

  # POST /admin/proposals/proposals
  # POST /admin/proposals/proposals.json
  def create
    @call = Admin::Proposals::Call.find(params[:call_id])
    
    if not @call.open then
      flash[:alert] = "Sorry. #{@call.name} isn't open yet. You cannot add a proposal for a closed call."
      redirect_to admin_proposals_calls_path
      return
    end
    
    @proposal = Admin::Proposals::Proposal.new(params[:admin_proposals_proposal])
    
    @proposal.call = @call
    
    #Set a proposal as late if created after the call deadline:
    if Time.now > @call.deadline then
      @proposal.late = true
    end

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
    @call = @admin_proposals_proposal.call
    
    authorize!(:edit, @admin_proposals_proposal)
    
    respond_to do |format|
      if @admin_proposals_proposal.update_attributes(params[:admin_proposals_proposal])
        format.html { redirect_to admin_proposals_call_proposal_path(@call, @admin_proposals_proposal), notice: 'Proposal was successfully updated.' }
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
  
  def approve
    @proposal = Admin::Proposals::Proposal.find(params[:id])
    @call = @proposal.call
    
    @proposal.approved = true
    @proposal.save
    
    authorize!(:approve, @proposal)
    
    respond_to do |format|
      flash[:success] = "#{@proposal.show_title} has been marked as approved"
      format.html { redirect_to admin_proposals_call_proposals_path(@call)}
      format.json { head :no_content }
    end
  end
  
  def reject
    @proposal = Admin::Proposals::Proposal.find(params[:id])
    @call = @proposal.call
    
    @proposal.approved = false
    @proposal.save
    
    respond_to do |format|
      flash[:success] = "#{@proposal.show_title} has been marked as rejected"
      format.html { redirect_to admin_proposals_call_proposals_path(@call)}
      format.json { head :no_content }
    end
  end
end
