##
# Admin controller for Opportunity. More details can be found there.
##
class Admin::OpportunitiesController < AdminController
  include GenericController

  load_and_authorize_resource

  ##
  # Overrides some index arguments.

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

    super
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

    super
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
      # format.json { head :no_content }
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
      # format.json { head :no_content }
    end
  end

  private

  def permitted_params
    # Do not include information about the approver and creator. That should only be settable by the controller.
    [:description, :show_email, :title, :expiry_date]
  end

  def includes_args
    [:creator]
  end

  def order_args
    ['expiry_date DESC']
  end
end
