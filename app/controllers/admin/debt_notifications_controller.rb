class Admin::DebtNotificationsController < AdminController
  # GET /admin/debt_notifications
  def index
    authorize! :read, Admin::DebtNotification

    @debt_notifications = Admin::DebtNotification.all
    @debt_notifications = @debt_notifications.search_for(params[:first_name], params[:last_name])
    @debt_notifications = @debt_notifications.order('sent_on ASC').paginate(page: params[:page], per_page: 15)
    @debt_notifications.all
  end
end
