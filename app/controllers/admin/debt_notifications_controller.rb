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
