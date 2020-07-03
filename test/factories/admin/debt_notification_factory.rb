FactoryBot.define do
  factory :initial_debt_notification, class: Admin::DebtNotification do
    association :user, factory: :member
    sent_on { Date.today - 20 }
    notification_type { :initial_notification }
  end

  factory :reminder_debt_notification, class: Admin::DebtNotification do
    association :user, factory: :member
    sent_on { Date.today - 5 }
    notification_type { :reminder }
  end
end
