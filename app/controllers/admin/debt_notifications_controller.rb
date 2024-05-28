class Admin::DebtNotificationsController < AdminController
  include GenericController

  load_and_authorize_resource

  private

  def resource_class
    Admin::DebtNotification
  end

  def order_args
    ['sent_on desc']
  end
end
