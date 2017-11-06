# == Schema Information
#
# Table name: admin_debt_notifications
#
#  id                :integer          not null, primary key
#  user_id           :integer
#  sent_on           :date
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  notification_type :integer
#
class Admin::DebtNotification < ActiveRecord::Base
  enum notification_type: %i[initial_notification reminder]
  belongs_to :user
  attr_accessible :user, :user_id, :sent_on, :notification_type

  def self.notified_since(date)
    # returns users who have been sent a notification since the given date
    return User.includes(:admin_debt_notifications).where('admin_debt_notifications.sent_on >?', date).references(:admin_debt_notifications).uniq
  end

  def self.search_for(user_fname, user_sname)
    user_ids = User.where('first_name LIKE ? AND last_name LIKE ?', "%#{user_fname}%", "%#{user_sname}%").ids
    notifications = where(user_id: user_ids)

    return notifications
  end
end
