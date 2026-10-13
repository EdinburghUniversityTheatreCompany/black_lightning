##
# Represents staffing that has many jobs. Users sign up for the Staffing_Job, not the Staffing.
#
# Each save (re)schedules a StaffingReminderJob.
#
# == Schema Information
#
# Table name: admin_staffings
# Database name: primary
#
#  id                    :integer          not null, primary key
#  counts_towards_debt   :boolean
#  end_time              :datetime
#  reminder_job_executed :boolean          default(FALSE)
#  show_title            :string(255)
#  slug                  :string(255)
#  start_time            :datetime
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  scheduled_job_id      :string(255)
#
# Indexes
#
#  index_admin_staffings_on_end_time    (end_time)
#  index_admin_staffings_on_slug        (slug)
#  index_admin_staffings_on_start_time  (start_time)
#
class Admin::Staffing < ApplicationRecord
  validates :show_title, :slug, :scheduled_job_id, length: { maximum: 255 }
  validates :show_title, presence: true
  validates :start_time, :end_time, presence: true, on: [ :create, :update ]

  after_save     :update_reminder
  after_save     :update_staffing_jobs, if: :saved_change_to_counts_towards_debt?
  after_save     :send_calendar_update_emails, if: :staffing_details_changed?
  before_destroy :cancel_scheduled_reminder

  has_many :staffing_jobs, as: :staffable, class_name: "Admin::StaffingJob", dependent: :destroy
  has_many :users, through: :staffing_jobs

  accepts_nested_attributes_for :staffing_jobs, reject_if: :all_blank, allow_destroy: true

  acts_as_url :show_title, url_attribute: :slug, sync_url: true, allow_duplicates: true

  normalizes :show_title, with: ->(value) { value&.strip }

  default_scope -> { order("start_time ASC") }

  scope :future, -> { where([ "end_time >= ?", DateTime.current ]) }
  scope :past, -> { where([ "end_time < ?", DateTime.current ]) }

  def self.ransackable_attributes(auth_object = nil)
    %w[start_time show_title end_time counts_towards_debt slug reminder_job_executed scheduled_job_id]
  end

  ##
  # Returns the number of jobs that have been filled
  ##
  def filled_jobs
    staffing_jobs.where.not(user_id: nil).count
  end

  private

  # Also runs before destroy: a reminder left queued for a deleted staffing would fail.
  # The queue database may be unreachable, so a failure is only logged.
  def cancel_scheduled_reminder
    return if scheduled_job_id.blank?

    SolidQueue::Job.find_by(active_job_id: scheduled_job_id)&.destroy
  rescue => e
    Rails.logger.warn "Could not cancel job #{scheduled_job_id}: #{e.message}"
  end

  ##
  # Update/schedule the reminder job for the staffing
  ##
  def update_reminder
    return unless self.start_time > DateTime.current

    # Don't schedule a new job if we're just marking the current job as executed
    return if saved_change_to_reminder_job_executed? && reminder_job_executed?

    cancel_scheduled_reminder

    job = StaffingReminderJob.set(wait_until: start_time.advance(hours: -2)).perform_later(id)

    # update_columns: a save here would run this callback again.
    self.update_columns(
      scheduled_job_id: job.job_id,
      reminder_job_executed: false
    )

    # Every reminder goes out again for the new time.
    staffing_jobs.update_all(reminder_sent_at: nil)
  end

  def staffing_details_changed?
    saved_change_to_show_title? || saved_change_to_start_time? || saved_change_to_end_time?
  end

  def send_calendar_update_emails
    staffing_jobs.where.not(user_id: nil).each do |job|
      job.bump_calendar_sequence
      StaffingMailer.calendar_invite(job).deliver_later
    end
  end

  # Reassociate staffing jobs if the count_towards_debt flag changes.
  def update_staffing_jobs
    staffing_jobs.each do |job|
      job.staffing_debt.update(admin_staffing_job: nil) if job.staffing_debt.present?
      job.associate_with_debt
    end

    # Unsure why this reload is needed, but otherwise some tests for staffing_jobs fail because they can't find the jobs associated with the staffing.
    reload
  end
end
