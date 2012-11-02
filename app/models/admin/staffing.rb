class Admin::Staffing < ActiveRecord::Base
   has_many :staffing_jobs, :class_name => "Admin::StaffingJob"
   
   accepts_nested_attributes_for :staffing_jobs, :reject_if => :all_blank, :allow_destroy => true
   
   validates :show_title, :date, :presence => true
   
   attr_accessible :show_title, :date, :staffing_jobs, :staffing_jobs_attributes
end
