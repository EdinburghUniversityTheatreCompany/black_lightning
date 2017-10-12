class Admin::DebtNotificationsController < AdminController
  before_action :set_admin_debt_notification, only: [:show, :edit, :update, :destroy]

  # GET /admin/debt_notifications
  def index
    @debt_notifications = Admin::DebtNotification.all
    if params[:user_fname].present?
      @debt_notifications = @debt_notifications.search_for(params[:user_fname],params[:user_sname])
    end
    @debt_notifications = @debt_notifications.order('sent_on ASC').paginate(page: params[:page], per_page: 15)
    @debt_notifications.all
  end

  # GET /admin/debt_notifications/1
  def show
  end

  # GET /admin/debt_notifications/new
  def new
    redirect_to admin_debt_notifications_path, notice:"Debt notifications shouldn't be created manually"
  end

  # GET /admin/debt_notifications/1/edit
  def edit
    redirect_to admin_debt_notifications_path, notice:"Debt notifications shouldn't be modified"
  end

  # POST /admin/debt_notifications
  def create
    redirect_to admin_debt_notifications_path, notice:"Debt notifications shouldn't be created manually"
  end

  # PATCH/PUT /admin/debt_notifications/1
  def update
    redirect_to admin_debt_notifications_path, notice:"Debt notifications shouldn't be modified"
  end

  # DELETE /admin/debt_notifications/1
  def destroy
    redirect_to admin_debt_notifications_path, notice:"Debt notifications shouldn't be destroyed"
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_admin_debt_notification
      @admin_debt_notification = Admin::DebtNotification.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def admin_debt_notification_params
      params.require(:admin_debt_notification).permit(:user_id, :sent_on)
    end
end
