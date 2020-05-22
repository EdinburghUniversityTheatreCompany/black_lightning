##
# Admin controller for Opportunity. More details can be found there.
##
class Admin::OpportunitiesController < AdminController
  load_and_authorize_resource

  ##
  # GET /admin/opportunities
  #
  # GET /admin/opportunities.json
  ##
  def index
    @title = 'Opportunities'
    @opportunities = @opportunities.includes(:creator)
                                   .order('expiry_date DESC')
                                   .paginate(page: params[:page], per_page: 15)

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @opportunities }
    end
  end

  ##
  # GET /admin/opportunity/1
  #
  # GET /admin/opportunity/1.json
  ##
  def show
    @title = @opportunity.title

    respond_to do |format|
      format.html
      format.json { render json: @opportunity }
    end
  end

  ##
  # GET /admin/opportunity/new
  #
  # GET /admin/opportunity/new.json
  ##
  def new
    # The title is set by the view.
    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @opportunity }
    end
  end

  ##
  # GET /admin/opportunity/1/edit
  ##
  def edit
    # The title is set by the view.
  end

  ##
  # POST /admin/opportunity
  #
  # POST /admin/opportunity.json
  ##
  def create
    @opportunity.creator = current_user

    # Make sure users cannot create an opportunity that is approved.
    # They should manually approve it.
    @opportunity.approved = false
    @opportunity.approver = nil

    respond_to do |format|
      if @opportunity.save
        format.html { redirect_to [:admin, @opportunity], notice: 'Opportunity was successfully created.' }
        format.json { render json: [:admin, @opportunity], status: :created, location: @opportunities }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: @opportunity.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # PUT /admin/opportunity/1
  #
  # PUT /admin/opportunity/1.json
  ##
  def update
    if can? :approve, @opportunity
      # Maintain the approval, but update the approver if it stays approved.
      @opportunity.approver = current_user if @opportunity.approved
    else
      @opportunity.approved = false
      @opportunity.approver = nil
    end

    respond_to do |format|
      if @opportunity.update(opportunity_params)
        format.html { redirect_to [:admin, @opportunity], notice: 'Opportunity was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: @opportunity.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/opportunity/1
  #
  # DELETE /admin/opportunity/1.json
  ##
  def destroy
    helpers.destroy_with_flash_message(@opportunity)

    respond_to do |format|
      format.html { redirect_to admin_opportunities_url }
      format.json { head :no_content }
    end
  end

  ##
  # PUT /admin/opportunity/1/approve
  #
  # PUT /admin/opportunity/1/approve.json
  ##
  def approve
    @opportunity.approved = true
    @opportunity.approver = current_user

    if @opportunity.save
      flash[:success] = "#{@opportunity.title} has been approved"
    else
      # I can see that this will work, but I cannot get it to fail.
      # :nocov:
      flash[:error] = "Could not approve #{@opportunity.title}"
      # :nocov:
    end

    respond_to do |format|
      format.html { redirect_to admin_opportunity_url(@opportunity) }
      format.json { head :no_content }
    end
  end

  ##
  # PUT /admin/opportunity/1/reject
  #
  # PUT /admin/opportunity/1/reject.json
  ##
  def reject
    @opportunity.approved = false
    @opportunity.approver = nil

    if @opportunity.save
      flash[:success] = "#{@opportunity.title} has been rejected"
    else
      # I can see that this will work, but I cannot get it to fail.
      # :nocov:
      flash[:error] = "Could not reject #{@opportunity.title}"
      # :nocov:
    end

    respond_to do |format|
      format.html { redirect_to admin_opportunity_url(@opportunity) }
      format.json { head :no_content }
    end
  end

  private

  def opportunity_params
    # Do not include information about the approver and creator. That should only be settable by the controller.
    params.require(:opportunity).permit(:description, :show_email, :title, :expiry_date)
  end
end
