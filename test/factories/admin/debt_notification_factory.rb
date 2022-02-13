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
FactoryBot.define do
  factory :initial_debt_notification, class: Admin::DebtNotification do
    association :user, factory: :member
    sent_on { Date.current - 20 }
    notification_type { :initial_notification }
  end

  factory :reminder_debt_notification, class: Admin::DebtNotification do
    association :user, factory: :member
    sent_on { Date.current - 5 }
    notification_type { :reminder }
  end
end
