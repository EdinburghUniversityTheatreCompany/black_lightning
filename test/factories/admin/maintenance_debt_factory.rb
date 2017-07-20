FactoryGirl.define do

  factory :maintenance_debt, class: Admin::MaintenanceDebt do
    association :user, factory: :member
    association :show, factory: :show
    due_by Date.today + 1
  end

  factory :overdue_maintenance_debt, parent: :staffing_debt do
    due_by Date.today - 1
  end

end
