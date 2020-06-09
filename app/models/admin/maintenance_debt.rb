# == Schema Information
#
# Table name: admin_maintenance_debts
#
#  id         :integer          not null, primary key
#  user_id    :integer
#  due_by     :date
#  show_id    :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  state      :integer          default(0)
#
class Admin::MaintenanceDebt < ApplicationRecord
  belongs_to :user
  belongs_to :show

  validates :due_by, :show_id, :user_id, presence: true

  enum state: %i[unfulfilled converted completed]
  # the progress of a maintenance debt is tracked by its state enum
  # with status being used to retrieve if the debt has become overdue and is causing debt

  def convert_to_staffing_debt
    staffing_debt = Admin::StaffingDebt.new
    staffing_debt.due_by = due_by
    staffing_debt.show_id = show_id
    staffing_debt.user_id = user_id
    staffing_debt.converted = true
    staffing_debt.save!
    self.state = :converted
    save!
  end

  def status(on_date = Date.today)
    case state
    when 'converted'
      return :converted
    when 'completed'
      return :completed
    when 'unfulfilled' then
      if due_by < on_date
        :causing_debt
      else
        :unfulfilled
      end
    end
  end

  def css_class
    case status
    when :unfulfilled
      'warning'
    when :converted
      'success'
    when :completed
      'success'
    when :causing_debt
      'error'
    end
  end
end
