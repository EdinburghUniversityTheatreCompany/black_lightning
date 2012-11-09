class Admin::Staffing < ActiveRecord::Base
   has_many :staffing_jobs, :class_name => "Admin::StaffingJob"

   # Having this as a belongs_to feels wrong, but since the id of the job needs to be stored in the staffing it is necessary.
   belongs_to  :reminder_job, :class_name => "::Delayed::Job"

   accepts_nested_attributes_for :staffing_jobs, :reject_if => :all_blank, :allow_destroy => true

   validates :show_title, :date, :presence => true

   attr_accessible :show_title, :date, :staffing_jobs, :staffing_jobs_attributes
end
