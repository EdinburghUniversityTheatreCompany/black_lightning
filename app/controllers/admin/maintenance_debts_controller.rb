# These views are very similar to those for staffing_debts, so if you have improvements for this, have a look if you can apply them there as well.
class Admin::MaintenanceDebtsController < AdminController
  include GenericController

  load_and_authorize_resource

  ##
  # Overrides load_index_resources
  ##

  # GET /admin/maintenance_debts/1
  def show
    @title = "Maintenance Debt for #{@maintenance_debt.user.name(current_user)}"

    super
  end

  # DELETE /admin/maintenance_debts/1
  def destroy
    @maintenance_debt.forgive

    if @maintenance_debt.save
      flash[:success] = 'The Maintenance Debt has been successfully marked as completed.'
    else
      # I hate using nocov but I cannot force this to fail and I can see that this code will work.
      # :nocov:
      flash[:error] = 'Error marking Maintenance Debt completed. The Theatre Manager Fairy could not be saved :('
      # :nocov:
    end

    respond_to do |format|
      format.html { redirect_to admin_maintenance_debts_path }
      format.json { head :no_content }
    end
  end

  # PUT
  def convert_to_staffing_debt
    @maintenance_debt.convert_to_staffing_debt

    respond_to do |format|
      format.html { redirect_to admin_maintenance_debts_url, notice: 'Maintenance Debt converted to Staffing Debt' }
      format.json { head :no_content }
    end
  end

  private

  def resource_class
    Admin::MaintenanceDebt
  end

  # Only allow a trusted parameter "white list" through.
  def permitted_params
    [:user_id, :due_by, :show_id, :state]
  end

  def load_index_resources
    @maintenance_debts, @q, show_fulfilled, @is_specific_user = helpers.shared_debt_load(@maintenance_debts, params[:show_non_members], params, [:user, :show, :maintenance_attendance])

    params[:show_fulfilled] = show_fulfilled ? '1' : '0'

    return @maintenance_debts
  end
end
