# == Schema Information
#
# Table name: admin_debt_notifications
#
# *id*::                <tt>integer, not null, primary key</tt>
# *user_id*::           <tt>integer</tt>
# *sent_on*::           <tt>date</tt>
# *created_at*::        <tt>datetime, not null</tt>
# *updated_at*::        <tt>datetime, not null</tt>
# *notification_type*:: <tt>integer</tt>
#--
# == Schema Information End
#++
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
