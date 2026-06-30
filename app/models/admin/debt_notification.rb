# == Schema Information
#
# Table name: admin_debt_notifications
# Database name: primary
#
#  id                :integer          not null, primary key
#  notification_type :integer
#  sent_on           :date
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  user_id           :integer
#
# Indexes
#
#  index_admin_debt_notifications_on_sent_on  (sent_on)
#  index_admin_debt_notifications_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Admin::DebtNotification < ApplicationRecord
  enum :notification_type,
    initial_notification: 0,
    reminder: 1

  belongs_to :user

  DISABLED_PERMISSIONS = %w[create update delete manage].freeze

  def self.default_scope
    order("sent_on DESC")
  end

  def self.ransackable_attributes(auth_object = nil)
    [ "notification_type", "sent_on" ]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "user" ]
  end
end
