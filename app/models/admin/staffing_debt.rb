class Admin::StaffingDebt < ActiveRecord::Base
  belongs_to :user
  belongs_to :show
  has_one :admin_staffing_job, :class_name => 'Admin::StaffingJob'

  validates :dueBy, presence: true
end
