# These views are very similar to those for maintenance_debts, so if you have improvements for this, have a look if you can apply them there as well.
class Admin::StaffingDebtsController < AdminController
  include GenericController

  load_and_authorize_resource

  ##
  # Overrides load_index_resources
  ##

  # GET /admin/staffing_debts/1
  def show
    @title = "Staffing Debt for #{@staffing_debt.user.name(current_user)}"

    @jobs = @staffing_debt.user.staffing_jobs.unassociated_staffing_jobs_that_count_towards_debt

    super
  end

  # New, Create, Edit, and Update are handled by the Generic Controller.

  # DELETE /admin/staffing_debts/1
  def destroy
    if @staffing_debt.forgive
      flash[:success] = 'The Staffing Debt has been successfully forgiven.'
    else
      # I hate using nocov but I cannot force this to fail and I can see that this code will work.
      # :nocov:
      flash[:error] = 'Error forgiving the Staffing Debt. The Front of House fairy has been resurrected :)'
      # :nocov:
    end

    respond_to do |format|
      format.html { redirect_to admin_staffing_debts_path }
      format.json { head :no_content }
    end
  end

  # Associates a debt with a staffing job.
  # PUT
  def assign
    if @staffing_debt.update(admin_staffing_job_id: params[:job_id])
      flash[:success] = 'The Staffing Debt has been successfully assigned a job.'
    else
      # I hate using nocov but I cannot force this to fail and I can see that this code will work.
      # :nocov:
      flash[:error] = 'There was an error assigning the Staffing Debt.'
      # :nocov:
    end

    respond_to do |format|
      format.html { redirect_to admin_staffing_debts_url }
      format.html { render :no_content }
    end
  end

  # PUT
  def unassign
    if @staffing_debt.update(admin_staffing_job_id: nil)
      flash[:success] = 'The Job is now removed from the Staffing Debt.'
    else
      # I hate using nocov but I cannot force this to fail and I can see that this code will work.
      # :nocov:
      flash[:error] = 'There was an error removing the Job from the the Staffing Debt.'
      # :nocov:
    end

    respond_to do |format|
      format.html { redirect_to admin_staffing_debts_url, notice: 'Job Removed' }
      format.html { render :no_content }
    end
  end

  private

  def resource_class
    Admin::StaffingDebt
  end

  def permitted_params
    [:user_id, :show_id, :due_by, :admin_staffing_job_id]
  end

  def load_index_resources
    @staffing_debts, @q, show_fulfilled, @is_specific_user = helpers.shared_debt_load(@staffing_debts, params[:show_non_members], params, [:user, :admin_staffing_job])

    params[:show_fulfilled] = show_fulfilled ? '1' : '0'

    return @staffing_debts
  end

  def edit_title
    "Edit Staffing Debt for #{@staffing_debt.user.name(current_user)}"
  end
end
