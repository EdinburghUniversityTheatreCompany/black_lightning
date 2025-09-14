##
# Represents staffing that has many jobs. Users sign up for the Staffing_Job, not the Staffing.
#
# A StaffingReminderJob will be scheduled to send out reminders, and updated whenever the staffing is saved.
#
# == Schema Information
#
# Table name: admin_staffings
#
# *id*::                  <tt>integer, not null, primary key</tt>
# *start_time*::          <tt>datetime</tt>
# *show_title*::          <tt>string(255)</tt>
# *created_at*::          <tt>datetime, not null</tt>
# *updated_at*::          <tt>datetime, not null</tt>
# *reminder_job_id*::     <tt>integer</tt>
# *reminder_job_executed*:: <tt>boolean, default: false</tt>
# *end_time*::            <tt>datetime</tt>
# *counts_towards_debt*:: <tt>boolean</tt>
# *slug*::                <tt>string(255)</tt>
#--
# == Schema Information End
#++
class Admin::Staffing < ApplicationRecord
  validates :show_title, presence: true
  validates :start_time, :end_time, presence: true, on: [ :create, :update ]

  after_save     :update_reminder
  after_save     :update_staffing_jobs, if: :saved_change_to_counts_towards_debt?

  has_many :staffing_jobs, as: :staffable, class_name: "Admin::StaffingJob", dependent: :destroy
  has_many :users, through: :staffing_jobs

  # Legacy: reminder_job_id field still exists in database but no longer used
  # TODO: Remove reminder_job_id column in future migration

  accepts_nested_attributes_for :staffing_jobs, reject_if: :all_blank, allow_destroy: true

  acts_as_url :show_title, url_attribute: :slug, sync_url: true, allow_duplicates: true

  normalizes :show_title, with: ->(value) { value&.strip }

  default_scope -> { order("start_time ASC") }

  scope :future, -> { where([ "end_time >= ?", DateTime.current ]) }
  scope :past, -> { where([ "end_time < ?", DateTime.current ]) }

  def self.ransackable_attributes(auth_object = nil)
    %w[start_time show_title end_time counts_towards_debt slug reminder_job_executed]
  end

  ##
  # Returns the number of jobs that have been filled
  ##
  def filled_jobs
    staffing_jobs.where.not(user_id: nil).count
  end

  private

  ##
  # Update/schedule the reminder job for the staffing
  ##
  def update_reminder
    return unless self.start_time > DateTime.current

    # Schedule new reminder job - duplicate prevention handled by reminder_job_executed flag
    StaffingReminderJob.set(wait_until: start_time.advance(hours: -2)).perform_later(id)

    # Reset execution flag for new job
    self.reminder_job_executed = false
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
