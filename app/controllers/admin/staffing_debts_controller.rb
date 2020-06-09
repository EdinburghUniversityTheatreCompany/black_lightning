# These views are very similar to those for maintenance_debts, so if you have improvements for this, have a look if you can apply them there as well.
class Admin::StaffingDebtsController < AdminController
  load_and_authorize_resource

  # GET /admin/staffing_debts
  def index
    @title = 'Staffing Debts'

    @staffing_debts, @q, @show_fulfilled, @is_specific_user = helpers.shared_debt_load(@staffing_debts, params, [:user, :admin_staffing_job])

    respond_to do |format|
      format.html
      format.json { render json: @staffing_debts }
    end
  end

  # GET /admin/staffing_debts/1
  def show
    @title = "Staffing Debt for #{@staffing_debt.user.name(current_user)}"

    @jobs = @staffing_debt.user.staffing_jobs.unassociated_staffing_jobs_that_count_towards_debt
  end

  # GET /admin/staffing_debts/new
  def new
    respond_to do |format|
      format.html
      format.json { render json: @staffing_debt }
    end
  end

  # POST /admin/staffing_debts
  def create
    respond_to do |format|
      if @staffing_debt.save
        format.html { redirect_to @staffing_debt, notice: 'The Staffing Debt was successfully created.' }
        format.json { head :no_content }
      else
        format.html { render 'new', status: :unprocessable_entity, notice: 'Failed to create new Staffing Debt. Please try again or contact IT' }
        format.json { render json: @staffing_debt.errors, status: :unprocessable_entity }
      end
    end
  end

  # GET /admin/staffing_debts/1/edit
  def edit
    respond_to do |format|
      format.html
      format.json { render json: @staffing_debt }
    end
  end

  # PATCH/PUT /admin/staffing_debts/1
  def update
    respond_to do |format|
      if @staffing_debt.update(staffing_debt_params)
        format.html { redirect_to @staffing_debt, notice: 'The Staffing Debt was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit', status: :unprocessable_entity, notice: 'Failed to update the Staffing Debt. Please try again or contact IT.' }
        format.json { render json: @staffing_debt.errors, status: :unprocessable_entity }
      end
    end
  end

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

  # Only allow a trusted parameter "white list" through.
  def staffing_debt_params
    params.require(:admin_staffing_debt).permit(:user_id, :show_id, :due_by, :admin_staffing_job_id)
  end
end
