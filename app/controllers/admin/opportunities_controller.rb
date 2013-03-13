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
    @title = "Opportunity"
    @opportunities = Opportunity.order("expiry_date DESC") \
                                .paginate(:page => params[:page], :per_page => 15) \
                                .includes(:creator) \
                                .all

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
    @opportunities = Opportunity.find(params[:id])
    @title = @opportunities.title
    respond_to do |format|
      format.html
      format.json { render json: @opportunities }
    end
  end

  ##
  # GET /admin/opportunity/new
  #
  # GET /admin/opportunity/new.json
  ##
  def new
    @opportunity = Opportunity.new
    @title = "Create Opportunity"
    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @opportunity }
    end
  end

  ##
  # GET /admin/opportunity/1/edit
  ##
  def edit
    @opportunity = Opportunity.find(params[:id])
    @title = "Edit #{@opportunity.title}"
  end

  ##
  # POST /admin/opportunity
  #
  # POST /admin/opportunity.json
  ##
  def create
    @opportunity = Opportunity.new(params[:opportunity])
    @opportunity.creator = current_user

    respond_to do |format|
      if @opportunity.save
        format.html { redirect_to [:admin, @opportunity], notice: 'Opportunity was successfully created.' }
        format.json { render json: [:admin, @opportunity], status: :created, location: @opportunities }
      else
        format.html { render "new" }
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
    @opportunity = Opportunity.find(params[:id])

    unless can? :approve, @opportunity
      @opportunity.approved = false
      @opportunity.approver = nil
    end

    respond_to do |format|
      if @opportunity.update_attributes(params[:opportunity])
        format.html { redirect_to [:admin, @opportunity], notice: 'Opportunity was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render "edit" }
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
    @opportunity = Opportunity.find(params[:id])
    @opportunity.destroy

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
    @opportunity = Opportunity.find(params[:id])

    authorize!(:approve, @opportunity)

    @opportunity.approved = true
    @opportunity.approver = current_user
    @opportunity.save!

    respond_to do |format|
      flash[:success] = "#{@opportunity.title} has been approved"
      format.html { redirect_to admin_opportunities_url }
      format.json { head :no_content }
    end
  end

  ##
  # PUT /admin/opportunity/1/reject
  #
  # PUT /admin/opportunity/1/reject.json
  ##
  def reject
    @opportunity = Opportunity.find(params[:id])

    authorize!(:reject, @opportunity)

    @opportunity.approved = false
    @opportunity.save!

    respond_to do |format|
      flash[:success] = "#{@opportunity.title} has been rejected"
      format.html { redirect_to admin_opportunities_url }
      format.json { head :no_content }
    end
  end
end
