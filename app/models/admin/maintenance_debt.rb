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

  def status(on_date = Date.current)
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
      'table-warning'
    when :converted
      'table-success'
    when :completed
      'table-success'
    when :causing_debt
      'table-danger'
    end
  end
end
