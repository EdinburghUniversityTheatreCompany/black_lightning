# == Schema Information
#
# Table name: admin_staffing_jobs
#
# *id*::             <tt>integer, not null, primary key</tt>
# *name*::           <tt>string(255)</tt>
# *staffable_id*::   <tt>integer</tt>
# *user_id*::        <tt>integer</tt>
# *created_at*::     <tt>datetime, not null</tt>
# *updated_at*::     <tt>datetime, not null</tt>
# *staffable_type*:: <tt>string(255)</tt>
#--
# == Schema Information End
#++

FactoryBot.define do
  factory :staffing_job, class: Admin::StaffingJob do
    name { generate(:random_string) }
    association :staffable, factory: :staffing_that_does_count_towards_debt

    transient do
      staffed { [ true, false ].sample }
    end

    after(:create) do |job, evaluator|
      if evaluator.staffed && job.user.nil?
        job.user = FactoryBot.create(:user)
        job.save
      end
    end
  end

  factory :staffed_staffing_job, parent: :staffing_job do
    association :user, factory: :user
    staffed { true }
  end

  factory :unstaffed_staffing_job, parent: :staffing_job do
    user { nil }
    staffed { false }
  end
end
