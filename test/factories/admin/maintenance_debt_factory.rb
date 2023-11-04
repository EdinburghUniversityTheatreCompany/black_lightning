# == Schema Information
#
# Table name: admin_maintenance_debts
#
# *id*::         <tt>integer, not null, primary key</tt>
# *user_id*::    <tt>integer</tt>
# *due_by*::     <tt>date</tt>
# *show_id*::    <tt>integer</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *state*::      <tt>integer, default("unfulfilled")</tt>
#--
# == Schema Information End
#++
FactoryBot.define do
  factory :maintenance_debt, class: Admin::MaintenanceDebt do
    association :user, factory: :member
    association :show, factory: :show
    due_by { Date.current + 1 }

    transient do
      with_attendance { false }
    end

    after(:create) do |maintenance_debt, evaluator|
      FactoryBot.create(:maintenance_attendance, maintenance_debt: maintenance_debt, user: evaluator.user) if evaluator.with_attendance
    end

    factory :overdue_maintenance_debt do
      due_by { Date.current - 1 }
    end
  end
end
