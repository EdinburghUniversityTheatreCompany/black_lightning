##
# Represents staffing that has many jobs. Users sign up for the Staffing_Job, not the Staffing.
#
# A Delayed::Job will be created to send out reminders, and updated whever the staffing is saved.
#
# If the Staffing is deleted, reminder_cleanup removes the Delayed::Job
#
# == Schema Information
#
# Table name: admin_staffings
#
# *id*::              <tt>integer, not null, primary key</tt>
# *start_time*::      <tt>datetime</tt>
# *show_title*::      <tt>string(255)</tt>
# *created_at*::      <tt>datetime, not null</tt>
# *updated_at*::      <tt>datetime, not null</tt>
# *reminder_job_id*:: <tt>integer</tt>
#--
# == Schema Information End
#++
##
class Admin::Staffing < ActiveRecord::Base
  after_save     :update_reminder
  before_destroy :reminder_cleanup

  default_scope -> { order('start_time ASC') }

  scope :future, -> { where(['end_time > ?', DateTime.now]) }
  scope :past, -> { where(['end_time < ?', DateTime.now]) }

  has_many :staffing_jobs, as: :staffable, class_name: 'Admin::StaffingJob', dependent: :destroy
  has_many :users, through: :staffing_jobs

  # Having this as a belongs_to feels wrong, but since the id of the job needs to be stored in the staffing it is necessary.
  belongs_to :reminder_job, class_name: '::Delayed::Job'

  accepts_nested_attributes_for :staffing_jobs, reject_if: :all_blank, allow_destroy: true

  validates :show_title, :start_time, presence: true

  attr_accessible :show_title, :start_time, :end_time, :staffing_jobs, :staffing_jobs_attributes

  ##
  # Returns the number of jobs that have been filled
  ##
  def filled_jobs
    staffing_jobs.where(['user_id is not null']).count
  end

  private

  ##
  # Remove the reminder_job when the Staffing is deleted to prevent the job from failing.
  ##
  def reminder_cleanup
    if reminder_job
      reminder_job.delete
    end
  end

  ##
  # Upstart_time the reminder job for the staffing
  ##
  def update_reminder
    if reminder_job.present?
      reminder_job.run_at = start_time.advance(hours: -2)
      reminder_job.save!
    else
      self.reminder_job = delay(run_at: start_time.advance(hours: -2)).send_reminder
      reminder_job.description = "Reminder for staffing #{id} - #{show_title} - #{I18n.l start_time, format: :short}"
      reminder_job.save!

      self.save!
    end
  end

  ##
  # Sends a reminder for staffing.
  #
  # Should only be called as a delayed job.
  ##
  def send_reminder
    if reminder_job.attempts > 0
      # Prevent the job from running more than once to prevent us spewing emails
      # if there is an error.
      fail reminder_job.last_error
    end

    errors = []

    staffing_jobs.each do |job|
      # Keep going to other users if sending to one fails for some reason.
      next if job.user.nil?
      user = job.user
      begin
        StaffingMailer.staffing_reminder(job).deliver_now
      rescue => e
        exception = e.exception "Error sending reminder to #{user.name}: " + e.message
        errors << exception
      end
    end

    if errors
      # Raise the errors now for the logs.
      errors.each do |e|
        fail e
      end
    end
  end
end
