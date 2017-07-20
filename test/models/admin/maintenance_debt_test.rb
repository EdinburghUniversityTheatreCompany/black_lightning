require 'test_helper'

class Admin::MaintenanceDebtTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
  test "can_convert_to_staffing_debt" do
    maintenance_debt = FactoryGirl.create(:maintenance_debt)
    assert_difference('Admin::MaintenanceDebt.count',-1) do
      assert_difference('Admin::StaffingDebt.count',+1) do
        maintenance_debt.convert_to_staffing_debt
      end
    end
    assert Admin::StaffingDebt.last.converted?
  end
end
