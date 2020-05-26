# == Schema Information
#
# Table name: admin_staffing_debts
#
#  id                    :integer          not null, primary key
#  user_id               :integer
#  show_id               :integer
#  due_by                :date
#  admin_staffing_job_id :integer
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  converted             :boolean
#  forgiven              :boolean          default(FALSE)
#
class Admin::StaffingDebt < ApplicationRecord
  validates :due_by, :show_id, :user_id, presence: true

  belongs_to :user
  belongs_to :show
  belongs_to :admin_staffing_job, class_name: 'Admin::StaffingJob'

  before_create :associate_staffing_debt_with_existing_staffing_job

  # the status of a staffing debt is determined by whether or not it has a staffing job and if that job is in the past
  # If you change this, please also change the functions that return upcoming debts in the user model.
  # Yes, that's not very DRY but now the functions in user.rb can be a database query instead of something with select.
  def status(on_date = Date.today)
    # note that :awaiting_staffing indicates the staffing slot has not been completed yet AND the debt deadline hasn't passed
    return :forgiven if forgiven
    return :completed_staffing if admin_staffing_job.try(:completed?)
    return :awaiting_staffing if admin_staffing_job.present?
    return :causing_debt if due_by < on_date

    return :not_signed_up
  end

  # returns if the staffing debt has been completed or not
  def fulfilled
    if admin_staffing_job.present?
      admin_staffing_job.completed?
    else
      forgiven
    end
  end

  # returns uncompleted staffing debts
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
      'warning'
    when :awaiting_staffing
      ''
    when :completed_staffing, :forgiven
      'success'
    when :causing_debt
      'error'
    end
  end

  private

  def associate_staffing_debt_with_existing_staffing_job
    # Only associate when the record is new(that's why it's in the after_create) and the record does not already have a staffing job.
    return if admin_staffing_job.present?

    self.admin_staffing_job = user.staffing_jobs.unassociated_staffing_jobs_that_count_towards_debt.first
  end
end
