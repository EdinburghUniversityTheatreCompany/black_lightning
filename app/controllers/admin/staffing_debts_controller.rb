class Admin::StaffingDebtsController < AdminController
  before_action :set_admin_staffing_debt, only: [:show, :edit, :update, :destroy]

  # GET /admin/staffing_debts
  def index
    @admin_staffing_debts = Admin::StaffingDebt.all
    @title = 'Staffing Debts'

    @start_date = Date.today - 80

    if can? :manage, Admin::StaffingDebt
      @q     = Admin::StaffingDebt.unscoped.search(params[:q])
      @sdebts = @q.result(distinct: true)
    else
      @sdebts = @admin_staffing_debts.where(user_id: current_user.id)
    end

    @sdebts = @sdebts.order('dueBy ASC').paginate(page: params[:page], per_page: 15)
    @sdebts = @sdebts.all
  end

  # GET /admin/staffing_debts/1
  def show
    boundryDate = Date.today - 80
    @admin_staffing_debt = Admin::StaffingDebt.find(params[:id])
    dateIds = @admin_staffing_debt.user.staffings.where('start_time >?', boundryDate.to_datetime).ids
    @jobs = @admin_staffing_debt.user.staffing_jobs.where(staffable_id: dateIds).where.not(id: Admin::StaffingDebt.pluck(:admin_staffing_job_id))

    authorize!(:read , @admin_staffing_debt)
  end


  # GET /admin/staffing_debts/new
  def new
    @admin_staffing_debt = Admin::StaffingDebt.new
  end

  # GET /admin/staffing_debts/1/edit
  def edit
  end

  def assign
    debt = Admin::StaffingDebt.find(params[:id])
    debt.update(admin_staffing_job_id: params[:jobid])
    debt.save!

    respond_to do |format|
      format.html { redirect_to admin_staffing_debts_url, notice: 'Job Assigned' }
      format.html { render :no_content }
    end
  end

  # POST /admin/staffing_debts
  def create
    @admin_staffing_debt = Admin::StaffingDebt.new(admin_staffing_debt_params)

    if @admin_staffing_debt.save
      redirect_to @admin_staffing_debt, notice: 'Staffing debt was successfully created.'
    else
      render :new
    end
  end

  # PATCH/PUT /admin/staffing_debts/1
  def update
    if @admin_staffing_debt.update(admin_staffing_debt_params)
      redirect_to @admin_staffing_debt, notice: 'Staffing debt was successfully updated.'
    else
      render :edit
    end
  end

  # DELETE /admin/staffing_debts/1
  def destroy
    @admin_staffing_debt.destroy
    redirect_to admin_staffing_debts_url, notice: 'Staffing debt was successfully destroyed.'
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_admin_staffing_debt
      @admin_staffing_debt = Admin::StaffingDebt.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def admin_staffing_debt_params
      params.require(:admin_staffing_debt).permit(:user_id, :show_id, :dueBy, :admin_staffing_job_id)
    end
end
