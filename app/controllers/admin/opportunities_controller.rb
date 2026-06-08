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
    assign_default_creator

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

  # Attribute the opportunity to the current user, unless a manager is explicitly
  # setting a different creator or an external submitter on someone else's behalf.
  def assign_default_creator
    manager_override = @opportunity.creator_id.present? ||
                       (@opportunity.submitter_name.present? && @opportunity.submitter_email.present?)
    return if can?(:manage, Opportunity) && manager_override

    @opportunity.creator = current_user
  end

  def permitted_params
    # Do not include information about the approver. That should only be settable by the controller.
    params = [ :description, :email_visibility, :contact_email, :title, :expiry_date,
               :company_id, :project, :author, :apply_url, :compensation_type, :experience_level,
               roles_attributes: [ :id, :position, :category, :note, :ordering, :_destroy ] ]

    # Only managers may attribute an opportunity to a different creator or an external submitter.
    params = [ :creator_id, :submitter_name, :submitter_email ] + params if can? :manage, Opportunity

    params
  end

  def includes_args
    [ :creator, :company, :roles ]
  end

  def order_args
    [ "expiry_date DESC" ]
  end

  def distinct_for_ransack
    false
  end
end
