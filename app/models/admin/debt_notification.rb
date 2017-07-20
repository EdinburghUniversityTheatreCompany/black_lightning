class Admin::DebtNotification < ActiveRecord::Base
  enum notification_type: [:initial_notification,:reminder]
  belongs_to :user

  def self.notified_since(date)
    #returns users who have been sent a notification since the given date
    return User.includes(:admin_debt_notifications).where('admin_debt_notifications.sent_on >?',date).references(:admin_debt_notifications).uniq
  end

  def self.search_for(user_fname,user_sname)
    userIDs = User.where('first_name LIKE ? AND last_name LIKE ?',"%#{user_fname}%","%#{user_sname}%").ids
    notifications = self.where(user_id: userIDs)

    return notifications
  end


end
