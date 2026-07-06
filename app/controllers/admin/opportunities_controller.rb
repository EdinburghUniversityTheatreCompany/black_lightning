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
      notified = notify_submitter(:approved)
      flash[:success] = "#{@opportunity.display_title} has been approved#{' and the submitter has been notified' if notified}"
    else
      # I can see that this will work, but I cannot get it to fail.
      # :nocov:
      flash[:error] = "Could not approve #{@opportunity.display_title}"
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
      notified = notify_submitter(:rejected)
      flash[:success] = "#{@opportunity.display_title} has been rejected#{' and the submitter has been notified' if notified}"
    else
      # I can see that this will work, but I cannot get it to fail.
      # :nocov:
      flash[:error] = "Could not reject #{@opportunity.display_title}"
      # :nocov:
    end

    respond_to do |format|
      format.html { redirect_to admin_opportunity_url(@opportunity) }
      # format.json { head :no_content }
    end
  end

  ##
  # PUT /admin/opportunity/1/close
  ##
  def close
    if @opportunity.close
      flash[:success] = "#{@opportunity.display_title} has been closed and no longer appears in the public listing"
    else
      # A valid record cannot fail to close, but legacy records may carry validation errors.
      # :nocov:
      flash[:error] = "Could not close #{@opportunity.display_title}"
      # :nocov:
    end

    redirect_to admin_opportunity_url(@opportunity)
  end

  private

  # Email the submitter about an approval/rejection decision, with the reviewer's optional note.
  # Returns true when an email was enqueued; skipped when there is no address to notify.
  def notify_submitter(decision)
    return false if @opportunity.notification_email.blank?

    OpportunityMailer.public_send(decision, @opportunity, params[:approval_note]).deliver_later
    true
  end

  # A manager entering an external submitter is still recorded as the creator, so the posting
  # shows as created on the submitter's behalf (see Opportunity#on_behalf_of?).
  def assign_default_creator
    return if can?(:manage, Opportunity) && @opportunity.creator_id.present?

    @opportunity.creator = current_user
  end

  def permitted_params
    # Do not include information about the approver. That should only be settable by the controller.
    params = [ :description, :email_visibility, :contact_email, :title, :expiry_date,
               :company_name, :project, :author, :dates, :location, :apply_url, :compensation_type, :experience_level,
               roles_attributes: [ :id, :position, :department_name, :note, :ordering, :_destroy ] ]

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
