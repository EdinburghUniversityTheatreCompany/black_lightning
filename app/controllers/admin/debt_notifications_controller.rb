class Admin::DebtNotificationsController < AdminController
  # GET /admin/debt_notifications
  def index
    authorize! :read, Admin::DebtNotification

    @title = 'Debt Notifications'

    @q = User.unscoped.ransack(params[:q])
    @users = @q.result(distinct: true)

    @debt_notifications = Admin::DebtNotification.where(user_id: @users.ids)
    @debt_notifications = @debt_notifications.order('sent_on ASC').paginate(page: params[:page], per_page: 15)
    @debt_notifications.all

    respond_to do |format|
      format.html
      format.json { render json: @debt_notifications }
    end
  end
end
