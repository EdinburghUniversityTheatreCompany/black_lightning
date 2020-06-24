class Admin::DebtNotificationsController < AdminController
  include GenericController

  load_and_authorize_resource

  private

  def base_index_query
    @q = Admin::DebtNotification.ransack(params[:q])
    @q.sorts = ['sent_on desc', 'user_full_name asc'] if @q.sorts.empty?

    return @q.result(distinct: true).includes(:user)
  end

  def resource_class
    Admin::DebtNotification
  end
end
