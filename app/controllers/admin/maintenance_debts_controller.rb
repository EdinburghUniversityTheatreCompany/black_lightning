class Admin::MaintenanceDebtsController < AdminController
  before_action :set_admin_maintenance_debt, only: [:show, :edit, :update, :destroy]

  # GET /admin/maintenance_debts
  def index
    @admin_maintenance_debts = Admin::MaintenanceDebt.all
    @title = 'Maintenance Debts'
    if can? :manage, Admin::MaintenanceDebt
      @q     = Admin::MaintenanceDebt.unscoped.search(params[:q])
      @mdebts = @q.result(distinct: true)
    else
      @mdebts = @admin_maintenance_debts.where(user_id: current_user.id)
    end

    @mdebts = @mdebts.paginate(page: params[:page], per_page: 15)
    @mdebts = @mdebts.all
  end

  # GET /admin/maintenance_debts/1
  def show
  end

  # GET /admin/maintenance_debts/new
  def new
    @admin_maintenance_debt = Admin::MaintenanceDebt.new
  end

  # GET /admin/maintenance_debts/1/edit
  def edit
  end

  # POST /admin/maintenance_debts
  def create
    @admin_maintenance_debt = Admin::MaintenanceDebt.new(admin_maintenance_debt_params)

    if @admin_maintenance_debt.save
      redirect_to @admin_maintenance_debt, notice: 'Maintenance debt was successfully created.'
    else
      render :new
    end
  end

  # PATCH/PUT /admin/maintenance_debts/1
  def update
    if @admin_maintenance_debt.update(admin_maintenance_debt_params)
      redirect_to @admin_maintenance_debt, notice: 'Maintenance debt was successfully updated.'
    else
      render :edit
    end
  end

  # DELETE /admin/maintenance_debts/1
  def destroy
    @admin_maintenance_debt.destroy
    redirect_to admin_maintenance_debts_url, notice: 'Maintenance debt was successfully destroyed.'
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_admin_maintenance_debt
      @admin_maintenance_debt = Admin::MaintenanceDebt.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def admin_maintenance_debt_params
      params.require(:admin_maintenance_debt).permit(:user_id, :dueBy, :show_id)
    end
end
