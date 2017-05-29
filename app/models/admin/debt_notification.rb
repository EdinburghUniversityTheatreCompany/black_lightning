class Admin::DebtNotification < ActiveRecord::Base
  belongs_to :user

  def notified_since(date)
    #returns users who have been sent a notification since the given date
    return User.includes(:admin_debt_notifications).where('admin_debt_notifications.sent_on >?',date).references(:admin_debt_notifications).uniq
  end


end
