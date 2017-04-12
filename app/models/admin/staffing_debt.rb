class Admin::StaffingDebt < ActiveRecord::Base
  belongs_to :user
  belongs_to :show
  belongs_to :admin_staffing_job, :class_name => 'Admin::StaffingJob'

  attr_accessible :admin_staffing_job_id

  validates :dueBy, presence: true

end
