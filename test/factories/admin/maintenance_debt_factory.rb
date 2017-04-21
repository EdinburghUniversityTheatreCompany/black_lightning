FactoryGirl.define do
  factory :maintenance_debt ,class: Admin::MaintenanceDebt do
    due_by  {Date.today + 1}

    after(:create) do |mdebt|
      mdebt.user = FactoryGirl.create(:user)
      mdebt.show = FactoryGirl.create(:show)
      mdebt.save
    end
  end
end
