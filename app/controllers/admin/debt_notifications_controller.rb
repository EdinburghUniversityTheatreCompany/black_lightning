class Admin::DebtNotificationsController < AdminController
  skip_load_and_authorize_resource
  # GET /admin/debt_notifications
  def index
    authorize! :index, Admin::DebtNotification
    @title = 'Debt Notifications'

    get_search_params(params)
    @q = Admin::DebtNotification.ransack(params[:q])
    @q.sorts = ['sent_on desc', 'user_full_name asc'] if @q.sorts.empty?

    @debt_notifications = @q.result(distinct: true).includes(:user).paginate(page: params[:page], per_page: 15)
    respond_to do |format|
      format.html
      format.json { render json: @debt_notifications }
    end
  end

  def get_search_params(params)
    q = params[:q] || {}
    @first_name = q.fetch(:user_first_name_cont, '')
    @last_name = q.fetch(:user_last_name_cont, '')
  end
end
