# These views are very similar to those for maintenance_debts, so if you have improvements for this, have a look if you can apply them there as well.
class Admin::StaffingDebtsController < AdminController
  before_action :set_admin_staffing_debt, only: [:show, :edit, :update, :destroy]

  # GET /admin/staffing_debts
  def index
    @title = 'Staffing Debts'

    if can? :read, Admin::StaffingDebt
      if params[:user_id].present?
        @sdebts = Admin::StaffingDebt.where(user_id: params[:user_id])
      else
        @show_fulfilled = params[:show_fulfilled]

        @first_name = params[:first_name]
        @last_name = params[:last_name]
        @show_name = params[:show_name]

        @sdebts = Admin::StaffingDebt.search_for(@first_name, @last_name, @show_name, @show_fulfilled)
      end
    else
      @sdebts = Admin::StaffingDebt.where(user_id: current_user.id).unfulfilled
    end

    @sdebts = @sdebts.order(due_by: :asc, show_id: :asc, user_id: :asc).paginate(page: params[:page], per_page: 15)
    @sdebts = @sdebts.all
  end

  # GET /admin/staffing_debts/1
  def show
    authorize!(:manage , @admin_staffing_debt)

    boundryDate = Date.today - 80
    @admin_staffing_debt = Admin::StaffingDebt.find(params[:id])
    dateIds = @admin_staffing_debt.user.staffings.where('start_time >?', boundryDate.to_datetime).ids
    @jobs = @admin_staffing_debt.user.staffing_jobs.where(staffable_id: dateIds).where.not(id: Admin::StaffingDebt.pluck(:admin_staffing_job_id), name: 'Committee Rep')
  end


  # GET /admin/staffing_debts/new
  def new
    @admin_staffing_debt = Admin::StaffingDebt.new
    @users = User.all
    @shows = Show.all
  end

  # GET /admin/staffing_debts/1/edit
  def edit
  end

  #associates a debt with a staffing job
  def assign
    authorize! :manage , Admin::StaffingDebt
    debt = Admin::StaffingDebt.find(params[:id])
    debt.update(admin_staffing_job_id: params[:jobid])
    debt.save!

    respond_to do |format|
      format.html { redirect_to admin_staffing_debts_url, notice: 'Job Assigned' }
      format.html { render :no_content }
    end
  end

  def unassign
    authorize! :manage , Admin::StaffingDebt
    debt = Admin::StaffingDebt.find(params[:id])
    debt.update(admin_staffing_job_id: nil)
    debt.save!

    respond_to do |format|
      format.html { redirect_to admin_staffing_debts_url, notice: 'Job Removed' }
      format.html { render :no_content }
    end
  end

  # POST /admin/staffing_debts
  def create
    @admin_staffing_debt = Admin::StaffingDebt.new(admin_staffing_debt_params)

    if @admin_staffing_debt.save
      redirect_to admin_staffing_debts_url, notice: 'Staffing debt was successfully created.'
    else
      redirect_to new_admin_staffing_debt_path, notice: 'Failed to create new staffing Debt, contact IT'
    end
  end

  # PATCH/PUT /admin/staffing_debts/1
  def update
    if @admin_staffing_debt.update(admin_staffing_debt_params)
      redirect_to admin_staffing_debts_url, notice: 'Staffing debt was successfully updated.'
    else
      render :edit
    end
  end

  # DELETE /admin/staffing_debts/1
  def destroy
    @admin_staffing_debt.forgive
    redirect_to admin_staffing_debts_url, notice: 'Staffing debt was successfully forgiven.'
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_admin_staffing_debt
      @admin_staffing_debt = Admin::StaffingDebt.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def admin_staffing_debt_params
      params.require(:admin_staffing_debt).permit(:user_id, :show_id, :due_by, :admin_staffing_job_id)
    end
end
