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
  validates :due_by, :show_id, :user_id, :state, presence: true
  validates :converted_from_maintenance_debt, inclusion: [ true, false ]

  belongs_to :user
  belongs_to :show, class_name: "Event", foreign_key: :show_id
  belongs_to :admin_staffing_job, class_name: "Admin::StaffingJob", optional: true

  after_save :associate_with_staffing_job
  after_destroy { associate_with_staffing_job(true) }


  def self.ransackable_attributes(auth_object = nil)
    %w[admin_staffing_job_id converted due_by forgiven show_id user_id]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[admin_staffing_job show user]
  end

  # the progress of staffing debt is tracked by its state enum
  # with status being used to retrieve if the debt has become overdue and is causing debt, or has been staffed.
  enum :state,
    normal: 0,
    converted: 1,
    forgiven: 2,
    expired: 3

  # the status of a staffing debt is determined by whether or not it has a staffing job and if that job is in the past
  # If you change this, please also change the functions that return upcoming debts in the user model.
  # Yes, that's not very DRY but now the functions in user.rb can be a database query instead of something with select.
  def status(on_date = Date.current)
    # note that :awaiting_staffing indicates the staffing slot has not been completed yet AND the debt deadline hasn't passed

    case state
    when "forgiven"
      :forgiven
    when "expired"
      :expired
    when "converted"
      :converted
    else
      return :completed_staffing if admin_staffing_job.try(:completed?)
      return :awaiting_staffing if admin_staffing_job.present?
      return :causing_debt if due_by < on_date

      :not_signed_up
    end
  end

  def formatted_status
    local_status.to_s.titleize
  end

  # Returns if the staffing debt no longer counts for debt.
  # However, the job has not necessarily been completed, so it could revert to count again.
  # This is the case UNLESS the status is normal and there is no associated staffing job.
  # This is because a converted, successful or forgiven debt always counts as completed.
  def fulfilled
    !(normal? && admin_staffing_job.blank?)
  end

  # Returns if the staffing debt has been irreversibly completed.
  # This is the case UNLESS the status is normal and there is no associated COMPLETED staffing job.
  def completed
    !(normal? && admin_staffing_job.try(:completed?))
  end

  # returns unfulfilled staffing debts.
  def self.unfulfilled
    where(admin_staffing_job: nil, state: :normal)
  end

  # Optimized scope for debt calculations - combines unfulfilled check with date filter
  def self.unfulfilled_before_date(on_date)
    where(admin_staffing_job: nil, state: :normal)
      .where("due_by < ?", on_date)
  end

  def self.unfulfilled_after_date(from_date)
    where(admin_staffing_job: nil, state: :normal)
      .where("due_by >= ?", from_date)
  end

  # Creates a new maintenance debt with the same attributes as this staffing debt.
  def convert_to_maintenance_debt
    ActiveRecord::Base.transaction do
      Admin::MaintenanceDebt.create(due_by: due_by, show_id: show_id, user_id: user_id, state: :normal, converted_from_staffing_debt: true)
      update(state: :converted, admin_staffing_job: nil)
    end
  end

  # Forgives this debt and frees up the associated staffing job.
  def forgive
    update(state: :forgiven, admin_staffing_job: nil)
  end

  def css_class
    case status.to_sym
    when :not_signed_up
      "table-warning"
    when :awaiting_staffing
      ""
    when :completed_staffing, :forgiven, :expired, :converted
      "table-success"
    when :causing_debt
      "table-danger"
    end
  end

  # Associates itself with the soonest upcoming Staffing Job.
  def associate_with_staffing_job(skip_check = false)
    relevant_keys = previous_changes.keys.excluding("created_at", "updated_at")

    # Clear the staffing_job if the state or user has changed, just in case.
    # Otherwise, setting a debt with an attached attendance to forgiven or converted
    # will keep the attendance attached.
    update(admin_staffing_job: nil) if relevant_keys.include?("state") || relevant_keys.include?("user_id")

    # Only reallocate if we are not checking for changes or the changes are not just the staffing job.
    # If we keep reallocating when the staffing job changes, we will end up with a loop.
    user.reallocate_staffing_debts if relevant_keys != [ "admin_staffing_job_id" ]
  end
end
