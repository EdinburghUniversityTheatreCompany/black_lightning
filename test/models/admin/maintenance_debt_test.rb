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
require 'test_helper'

class Admin::MaintenanceDebtTest < ActiveSupport::TestCase
  setup do
    @maintenance_debt = FactoryBot.create(:maintenance_debt)
  end

  ##
  # Other
  ##
  test 'can convert to staffing debt' do
    assert_difference('Admin::MaintenanceDebt.unfulfilled.count', -1) do
      assert_no_difference('Admin::MaintenanceDebt.count') do
        assert_difference('Admin::StaffingDebt.count', +1) do
          @maintenance_debt.convert_to_staffing_debt
        end
      end
    end
    assert Admin::StaffingDebt.last.converted_from_maintenance_debt, 'The converted_from_maintenance_debt is not set on a staffing debt converted from a maintenance debt.'
  end

  test 'get status and CSS class' do
    @maintenance_debt.state = :converted
    assert_equal :converted, @maintenance_debt.status
    assert_equal 'Converted', @maintenance_debt.formatted_status
    assert_equal 'table-success', @maintenance_debt.css_class

    @maintenance_debt.state = :forgiven
    assert_equal :forgiven, @maintenance_debt.status
    assert_equal 'Forgiven', @maintenance_debt.formatted_status
    assert_equal 'table-success', @maintenance_debt.css_class

    @maintenance_debt.state = :normal
    assert_equal :unfulfilled, @maintenance_debt.status(@maintenance_debt.due_by.advance(days: -1))
    assert_equal 'Unfulfilled', @maintenance_debt.formatted_status(@maintenance_debt.due_by.advance(days: -1))
    assert_equal 'table-warning', @maintenance_debt.css_class(@maintenance_debt.due_by.advance(days: -1))

    assert_equal :causing_debt, @maintenance_debt.status(@maintenance_debt.due_by.advance(days: 1))
    assert_equal 'Causing Debt', @maintenance_debt.formatted_status(@maintenance_debt.due_by.advance(days: 1))
    assert_equal 'table-danger', @maintenance_debt.css_class(@maintenance_debt.due_by.advance(days: 1))

    @maintenance_debt.maintenance_attendance = FactoryBot.create(:maintenance_attendance, user: @maintenance_debt.user)
    assert_equal :completed, @maintenance_debt.status
    assert_equal "Completed on #{@maintenance_debt.maintenance_attendance.date}", @maintenance_debt.formatted_status
    assert_equal 'table-success', @maintenance_debt.css_class
  end
end
