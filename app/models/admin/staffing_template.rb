class Admin::StaffingTemplate < ActiveRecord::Base
  has_many :staffing_jobs, :as => :staffable, :class_name => "Admin::StaffingJob"

  accepts_nested_attributes_for :staffing_jobs, :reject_if => :all_blank, :allow_destroy => true

  validates :name, :presence => true

  attr_accessible :name, :staffing_jobs, :staffing_jobs_attributes
end
