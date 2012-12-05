# == Schema Information
#
# Table name: admin_staffings
#
#  id              :integer          not null, primary key
#  date            :datetime
#  show_title      :string(255)
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  reminder_job_id :integer
#

class Admin::Staffing < ActiveRecord::Base
  before_destroy :job_cleanup

  default_scope order("date ASC")

  scope :future, where(['date > ?', DateTime.now])
  scope :past, where(['date < ?', DateTime.now])

  has_many :staffing_jobs, :class_name => "Admin::StaffingJob"

   # Having this as a belongs_to feels wrong, but since the id of the job needs to be stored in the staffing it is necessary.
  belongs_to :reminder_job, :class_name => "::Delayed::Job"

  accepts_nested_attributes_for :staffing_jobs, :reject_if => :all_blank, :allow_destroy => true

  validates :show_title, :date, :presence => true

  attr_accessible :show_title, :date, :staffing_jobs, :staffing_jobs_attributes

  def filled_jobs
    self.staffing_jobs.where(['user_id is not null']).count
  end

  private
  def job_cleanup
    if reminder_job then
      reminder_job.delete
    end
  end
end
