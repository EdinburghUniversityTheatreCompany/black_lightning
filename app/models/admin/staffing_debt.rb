# == Schema Information
#
# Table name: admin_staffing_debts
#
# *id*::                    <tt>integer, not null, primary key</tt>
# *user_id*::               <tt>integer</tt>
# *show_id*::               <tt>integer</tt>
# *due_by*::                <tt>date</tt>
# *admin_staffing_job_id*:: <tt>integer</tt>
# *created_at*::            <tt>datetime, not null</tt>
# *updated_at*::            <tt>datetime, not null</tt>
# *converted*::             <tt>boolean</tt>
# *forgiven*::              <tt>boolean, default(FALSE)</tt>
#--
# == Schema Information End
#++
class Admin::StaffingDebt < ApplicationRecord
  validates :due_by, :show_id, :user_id, presence: true

  belongs_to :user
  belongs_to :show
  belongs_to :admin_staffing_job, class_name: 'Admin::StaffingJob', optional: true

  before_create :associate_staffing_debt_with_existing_staffing_job

  default_scope { includes(:user) }

  # the status of a staffing debt is determined by whether or not it has a staffing job and if that job is in the past
  # If you change this, please also change the functions that return upcoming debts in the user model.
  # Yes, that's not very DRY but now the functions in user.rb can be a database query instead of something with select.
  def status(on_date = Date.current)
    # note that :awaiting_staffing indicates the staffing slot has not been completed yet AND the debt deadline hasn't passed
    return :forgiven if forgiven
    return :completed_staffing if admin_staffing_job.try(:completed?)
    return :awaiting_staffing if admin_staffing_job.present?
    return :causing_debt if due_by < on_date

    return :not_signed_up
  end

  # returns if the staffing debt has been completed or not.
  def fulfilled
    if admin_staffing_job.present?
      admin_staffing_job.completed?
    else
      forgiven
    end
  end

  # returns unfulfilled staffing debts.
  def self.unfulfilled
    fulfilled_ids = all.map { |debt| debt.fulfilled ? debt.id : nil }
    return where.not(id: fulfilled_ids)
  end

  def forgive
    self.forgiven = true
    self.admin_staffing_job = nil
    return save
  end

  def css_class
    case status.to_sym
    when :not_signed_up
      'table-warning'
    when :awaiting_staffing
      ''
    when :completed_staffing, :forgiven
      'table-success'
    when :causing_debt
      'table-danger'
    end
  end

  private

  def associate_staffing_debt_with_existing_staffing_job
    # Only associate when the record is new(that's why it's in the after_create) and the record does not already have a staffing job.
    return if admin_staffing_job.present?

    self.admin_staffing_job = user.staffing_jobs.unassociated_staffing_jobs_that_count_towards_debt.first
  end
end
