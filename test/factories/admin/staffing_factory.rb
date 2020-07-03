# == Schema Information
#
# Table name: admin_staffings
#
# *id*::                  <tt>integer, not null, primary key</tt>
# *start_time*::          <tt>datetime</tt>
# *show_title*::          <tt>string(255)</tt>
# *created_at*::          <tt>datetime, not null</tt>
# *updated_at*::          <tt>datetime, not null</tt>
# *reminder_job_id*::     <tt>integer</tt>
# *end_time*::            <tt>datetime</tt>
# *counts_towards_debt*:: <tt>boolean</tt>
# *slug*::                <tt>string(255)</tt>
#--
# == Schema Information End
#++

FactoryBot.define do
  factory :staffing, class: Admin::Staffing do
    show_title   { generate(:random_string) }

    start_time   { generate(:random_future_date) + 3.days }
    end_time     { start_time.advance(hours: rand(0.2..3.0)) }

    transient do
      unstaffed_job_count { 0 }
      staffed_job_count { 0 }
    end

    after(:create) do |staffing, evaluator|
      FactoryBot.create_list(:unstaffed_staffing_job, evaluator.unstaffed_job_count, staffable: staffing)
      FactoryBot.create_list(:staffed_staffing_job, evaluator.staffed_job_count, staffable: staffing)
    end
  end

  factory :staffing_that_does_count_towards_debt, parent: :staffing do
    counts_towards_debt { true }
  end

  factory :staffing_that_does_not_count_towards_debt, parent: :staffing do
    counts_towards_debt { false }
  end
end
