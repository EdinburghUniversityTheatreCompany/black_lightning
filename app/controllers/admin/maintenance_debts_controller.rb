
# These views are very similar to those for staffing_debts, so if you have improvements for this, have a look if you can apply them there as well.
class Admin::MaintenanceDebtsController < AdminController
  before_action :set_admin_maintenance_debt, only: [:show, :edit, :update, :destroy]

  # GET /admin/maintenance_debts
  def index
    @title = 'Maintenance Debts'

    if can? :read, Admin::MaintenanceDebt
      if params[:user_id].present?
        @mdebts = Admin::MaintenanceDebt.where(user_id: params[:user_id])
      else
        @show_fulfilled = params[:show_fulfilled]

        @first_name = params[:first_name]
        @last_name = params[:last_name]
        @show_name = params[:show_name]

        @mdebts = Admin::MaintenanceDebt.search_for(@first_name, @last_name, @show_name, @show_fulfilled)
      end
    else
      @mdebts = @admin_maintenance_debts.where(user_id: current_user.id).unfulfilled
    end

    @mdebts = @mdebts.order(due_by: :asc, show_id: :asc, user_id: :asc).paginate(page: params[:page], per_page: 15)
    @mdebts = @mdebts.all
  end

  # GET /admin/maintenance_debts/1
  def show
    @admin_maintenance_debt = Admin::MaintenanceDebt.find(params[:id])
    authorize!(:read, @admin_maintenance_debt)
  end

  # GET /admin/maintenance_debts/new
  def new
    @admin_maintenance_debt = Admin::MaintenanceDebt.new
    @users = User.all
    @shows = Show.all
  end

  # GET /admin/maintenance_debts/1/edit
  def edit
  end

  def convert_to_staffing_debt
    authorize! :manage, Admin::MaintenanceDebt
    mdebt = Admin::MaintenanceDebt.find(params[:id])
    mdebt.convert_to_staffing_debt()

    respond_to do |format|
      format.html { redirect_to admin_maintenance_debts_url, notice: 'Debt converted to Staffing Debt' }
      format.html { render :no_content }
    end
  end

  # POST /admin/maintenance_debts
  def create
    @admin_maintenance_debt = Admin::MaintenanceDebt.new(admin_maintenance_debt_params)

    if @admin_maintenance_debt.save
      redirect_to @admin_maintenance_debt, notice: 'Maintenance debt was successfully created.'
    else
      redirect_to new_admin_maintenance_debt_url, notice: 'Failed to create new Maintenance Debt contact IT'
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
    @admin_maintenance_debt.state = :completed
    if @admin_maintenance_debt.save
      redirect_to admin_maintenance_debts_url, notice: 'Maintenance debt completed.'
    else
      redirect_to admin_maintenance_debts_url, notice: 'Error marking debt completed'
    end
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_admin_maintenance_debt
    @admin_maintenance_debt = Admin::MaintenanceDebt.find(params[:id])
  end

  # Only allow a trusted parameter "white list" through.
  def admin_maintenance_debt_params
    params.require(:admin_maintenance_debt).permit(:user_id, :due_by, :show_id, :state)
  end
end
