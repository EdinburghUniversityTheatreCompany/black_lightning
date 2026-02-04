# == Schema Information
#
# Table name: admin_staffing_debts
#
# *id*::                    <tt>integer, not null, primary key</tt>
# *user_id*::               <tt>integer</tt>
# *show_id*::               <tt>integer</tt>
# *due_by*::                <tt>date</tt>
# *admin_staffing_job_id*:: <tt>integer</tt>
# *created_at*::            <tt>datetime, not null</tt>
# *updated_at*::            <tt>datetime, not null</tt>
# *converted*::             <tt>boolean</tt>
# *forgiven*::              <tt>boolean, default(FALSE)</tt>
#--
# == Schema Information End
#++
FactoryBot.define do
  factory :staffing_debt, class: Admin::StaffingDebt do
    association :user, factory: :member
    show { Show.first || FactoryBot.create(:show) }
    state { :normal }
    due_by { Date.current + 1 }
    converted_from_maintenance_debt { false }

    transient do
      with_staffing_job { false }
    end

    after(:create) do |staffing_debt, evaluator|
      staffing_job = FactoryBot.create(:staffing_job, staffing_debt: staffing_debt, user: evaluator.user) if evaluator.with_staffing_job
      staffing_debt.update(admin_staffing_job: staffing_job)
    end

    factory :overdue_staffing_debt do
      due_by { Date.current - 1 }
    end
  end
end
