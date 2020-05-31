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
class Admin::DebtNotification < ApplicationRecord
  enum notification_type: %i[initial_notification reminder]
  belongs_to :user

  DISABLED_PERMISSIONS = %w[create update delete manage].freeze

  def self.default_scope
    order('sent_on DESC')
  end
end
