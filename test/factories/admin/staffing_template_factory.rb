# == Schema Information
#
# Table name: admin_staffing_templates
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++

FactoryGirl.define do
  factory :staffing_template, class: Admin::StaffingTemplate do
    name   { generate(:random_string) }

    transient do
      job_count 0
    end

    after(:create) do |staffing_template, evaluator|
      FactoryGirl.create_list(:staffing_job, evaluator.job_count, staffable: staffing_template)
    end
  end
end
