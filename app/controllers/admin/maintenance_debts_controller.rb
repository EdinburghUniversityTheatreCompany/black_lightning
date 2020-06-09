# These views are very similar to those for staffing_debts, so if you have improvements for this, have a look if you can apply them there as well.
class Admin::MaintenanceDebtsController < AdminController
  load_and_authorize_resource

  # GET /admin/maintenance_debts
  def index
    @title = 'Maintenance Debts'

    @maintenance_debts, @q, @show_fulfilled, @is_specific_user = helpers.shared_debt_load(@maintenance_debts, params, [:user, :show])

    respond_to do |format|
      format.html
      format.json { render json: @maintenance_debts }
    end
  end

  # GET /admin/maintenance_debts/1
  def show
    @title = "Maintenance Debt for #{@maintenance_debt.user.name(current_user)}"

    respond_to do |format|
      format.html
      format.json { render json: @maintenance_debt }
    end
  end

  # GET /admin/maintenance_debts/new
  def new
    respond_to do |format|
      format.html
      format.json { render json: @maintenance_debt }
    end
  end

  # POST /admin/maintenance_debts
  def create
    respond_to do |format|
      if @maintenance_debt.save
        format.html { redirect_to @maintenance_debt, notice: 'The Maintenance Debt was successfully created.' }
        format.json { head :no_content }
      else
        format.html { render 'new', status: :unprocessable_entity, notice: 'Failed to create new Maintenance Debt. Please try again or contact IT' }
        format.json { render json: @maintenance_debt.errors, status: :unprocessable_entity }
      end
    end
  end

  # GET /admin/maintenance_debts/1/edit
  def edit
    respond_to do |format|
      format.html
      format.json { render json: @maintenance_debt }
    end
  end

  # PATCH/PUT /admin/maintenance_debts/1
  def update
    respond_to do |format|
      if @maintenance_debt.update(maintenance_debt_params)
        format.html { redirect_to @maintenance_debt, notice: 'The Maintenance Debt was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit', status: :unprocessable_entity, notice: 'Failed to update the Maintenance Debt. Please try again or contact IT.' }
        format.json { render json: @maintenance_debt.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /admin/maintenance_debts/1
  def destroy
    @maintenance_debt.state = :completed

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

  # Only allow a trusted parameter "white list" through.
  def maintenance_debt_params
    params.require(:admin_maintenance_debt).permit(:user_id, :due_by, :show_id, :state)
  end
end
