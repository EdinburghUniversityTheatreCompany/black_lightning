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

  # New, Edit, and Update are handled by the Generic Controller.
  def create
    get_resource.state = :normal
    get_resource.converted_from_maintenance_debt = :false

    super
  end

  # PUT /admin/staffing_debts/1
  def forgive
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
      # format.json { head :no_content }
    end
  end

  # PUT
  def convert_to_maintenance_debt
    @staffing_debt.convert_to_maintenance_debt

    respond_to do |format|
      format.html { redirect_to admin_staffing_debts_url, notice: 'Staffing Debt converted to Maintenance Debt' }
      # format.json { head :no_content }
    end
  end

  private

  def resource_class
    Admin::StaffingDebt
  end

  def permitted_params
    [:user_id, :show_id, :due_by, :state, :admin_staffing_job_id]
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
