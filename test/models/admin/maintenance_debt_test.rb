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

  test 'can convert to staffing debt' do
    assert_difference('Admin::MaintenanceDebt.unfulfilled.count', -1) do
      assert_no_difference('Admin::MaintenanceDebt.count') do
        assert_difference('Admin::StaffingDebt.count', +1) do
          @maintenance_debt.convert_to_staffing_debt
        end
      end
    end
    assert Admin::StaffingDebt.last.converted?
  end

  test 'get status' do
    @maintenance_debt.state = :converted
    assert_equal :converted, @maintenance_debt.status
    @maintenance_debt.state = :completed
    assert_equal :completed, @maintenance_debt.status

    @maintenance_debt.state = :unfulfilled
    assert_equal :unfulfilled, @maintenance_debt.status(@maintenance_debt.due_by.advance(days: -1))
    assert_equal :causing_debt, @maintenance_debt.status(@maintenance_debt.due_by.advance(days: 1))
  end

  test 'should return the correct css class' do
    helper_compare_css_class 'success', :completed
    helper_compare_css_class 'success', :converted

    @maintenance_debt.due_by = Date.current.advance(days: 1)
    helper_compare_css_class'warning', :unfulfilled

    @maintenance_debt.due_by = Date.current.advance(days: -1)
    helper_compare_css_class 'error', :unfulfilled
  end

  def helper_compare_css_class(expected_class, state)
    @maintenance_debt.state = state
    assert_equal expected_class, @maintenance_debt.css_class
  end
end
