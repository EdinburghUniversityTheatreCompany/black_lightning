##
# Represents staffing that has many jobs. Users sign up for the Staffing_Job, not the Staffing.
#
# Note that a Delayed::Job will be created for the Staffing to send out reminders.
# Ensure that the Delayed::Job is updated to run at the correct time if the Staffing time has changed.
#--
# TODO: Move the above logic into the model.
#++
# If the Staffing is deleted, job_cleanup removes the Delayed::Job
#
# == Schema Information
#
# Table name: admin_staffings
#
# *id*::              <tt>integer, not null, primary key</tt>
# *date*::            <tt>datetime</tt>
# *show_title*::      <tt>string(255)</tt>
# *created_at*::      <tt>datetime, not null</tt>
# *updated_at*::      <tt>datetime, not null</tt>
# *reminder_job_id*:: <tt>integer</tt>
#--
# == Schema Information End
#++
##
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

  ##
  # Returns the number of jobs that have been filled
  ##
  def filled_jobs
    self.staffing_jobs.where(['user_id is not null']).count
  end

  private
  ##
  # Remove the reminder_job when the Staffing is deleted to prevent the job from failing.
  ##
  def job_cleanup
    if reminder_job then
      reminder_job.delete
    end
  end
end
