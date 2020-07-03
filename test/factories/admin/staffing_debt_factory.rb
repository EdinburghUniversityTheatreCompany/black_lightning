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
    association :show, factory: :show
    due_by { Date.today + 1 }

    factory :overdue_staffing_debt do
      due_by { Date.today - 1 }
    end
  end
end
