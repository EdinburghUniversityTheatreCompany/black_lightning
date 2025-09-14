# == Schema Information
#
# Table name: admin_maintenance_debts
#
# *id*::         <tt>integer, not null, primary key</tt>
# *user_id*::    <tt>integer</tt>
# *due_by*::     <tt>date</tt>
# *show_id*::    <tt>integer</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *state*::      <tt>integer, default("unfulfilled")</tt>
#--
# == Schema Information End
#++
class Admin::MaintenanceDebt < ApplicationRecord
  belongs_to :user
  belongs_to :show
  belongs_to :maintenance_attendance, optional: true

  validates :due_by, :show_id, :user_id, :state, presence: true
  validates :converted_from_staffing_debt, inclusion: [ true, false ]

  after_save :associate_with_attendance
  after_destroy { associate_with_attendance(true) }

  # the progress of a maintenance debt is tracked by its state enum
  # with status being used to retrieve if the debt has become overdue and is causing debt
  enum :state,
    normal: 0,
    converted: 1,
    forgiven: 2,
    expired: 3

  def self.ransackable_attributes(auth_object = nil)
    %w[created_at due_by show_id state user_id user show]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[show user]
  end

  # A maintenance debt is fulfilled if it is either: attended, converted, or forgiven. Otherwise, it is not fulfilled.
  # Or phrased differently, if the state is normal and there is no maintenance attendance, it is not fulfilled yet.
  def self.unfulfilled
    where(state: 0).where.missing(:maintenance_attendance)
  end

  # Optimized scope for debt calculations - combines unfulfilled check with date filter
  def self.unfulfilled_before_date(on_date)
    where(state: :normal)
      .where.missing(:maintenance_attendance)
      .where("due_by < ?", on_date)
  end

  def self.unfulfilled_after_date(from_date)
    where(state: :normal)
      .where.missing(:maintenance_attendance)
      .where("due_by >= ?", from_date)
  end

  # See above for an explanation.
  def unfulfilled?
    state == "normal" && maintenance_attendance.nil?
  end

  def convert_to_staffing_debt
    ActiveRecord::Base.transaction do
      Admin::StaffingDebt.create(due_by: due_by, show_id: show_id, user_id: user_id, state: :normal, converted_from_maintenance_debt: true)
      update(state: :converted, maintenance_attendance: nil)
    end
  end

  def forgive
    update(state: :forgiven)
  end

  def status(on_date = Date.current)
    case state
    when "forgiven"
      :forgiven
    when "expired"
      :expired
    when "converted"
      :converted
    else
      if maintenance_attendance.present?
        return :completed
      end

      if due_by < on_date
        :causing_debt
      else
        :unfulfilled
      end
    end
  end

  def formatted_status(on_date = Date.current)
    local_status = status(on_date)

    if local_status == :completed && maintenance_attendance.present?
      "Completed on #{maintenance_attendance.date}"
    else
      local_status.to_s.titleize
    end
  end

  def css_class(on_date = Date.current)
    case status(on_date)
    when :unfulfilled
      "table-warning"
    when :converted, :completed, :forgiven, :expired
      "table-success"
    when :causing_debt
      "table-danger"
    end
  end

  # Associates itself with the soonest upcoming Maintenance Attendance
  def associate_with_attendance(skip_check = false)
    relevant_keys = previous_changes.keys.excluding("created_at", "updated_at")

    # Clear the attendance if the state has changed, just in case.
    # Otherwise, setting a debt with an attached attendance to forgiven or converted
    # will keep the attendance attached.
    update(maintenance_attendance: nil) if relevant_keys.include?("state")

    # Only reallocate if we are not checking for changes or the changes are not just the attendance.
    # if we keep reallocating when the attendance changes, we will end up with a loop.
    user.reallocate_maintenance_debts if skip_check || relevant_keys != [ "maintenance_attendance_id" ]
  end
end
