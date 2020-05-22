# These views are very similar to those for staffing_debts, so if you have improvements for this, have a look if you can apply them there as well.
class Admin::MaintenanceDebtsController < AdminController
  load_and_authorize_resource

  # GET /admin/maintenance_debts
  def index
    @title = 'Maintenance Debts'

    get_search_params(params)

    @q = Admin::MaintenanceDebt.ransack(params[:q])
    @q.sorts = ['due_by asc', 'show_name asc', 'user_full_name asc'] if @q.sorts.empty?

    @maintenance_debts = @q.result.includes(:user, :show).accessible_by(current_ability)

    @is_specific_user = params[:user_id].present? || Admin::MaintenanceDebt.accessible_by(current_ability).map { |debt| debt.user.id }.uniq.count < 2

    if params[:user_id].present?
      @maintenance_debts = @maintenance_debts.where(user_id: params[:user_id])

      # If we are just displaying one user, also display the fulfilled debts even if the box is not ticked.
      @show_fulfilled = true
      @is_specific_user = true
    elsif Admin::MaintenanceDebt.accessible_by(current_ability).map { |debt| debt.user.id }.uniq.count < 2
      @is_specific_user = true
      @show_fulfilled = true
    end

    @maintenance_debts = @maintenance_debts.uncompleted unless @show_fulfilled
    @maintenance_debts = @maintenance_debts.paginate(page: params[:page], per_page: 30) unless @is_specific_user

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

  def get_search_params(params)
    q = params[:q] || {}
    @full_name = q.fetch(:user_full_name_cont, '')
    @show_name = q.fetch(:show_name_cont, '')
    @show_fulfilled = params.fetch(:show_fulfilled, nil) == '1'
  end
end
