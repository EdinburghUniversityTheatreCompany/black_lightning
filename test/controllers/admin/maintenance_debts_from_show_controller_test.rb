require 'test_helper'

class Admin::ShowMaintenanceDebtsControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryGirl.create(:admin)
    @show = FactoryGirl.create(:show)
    @show.maintenance_debt_start = Date.today + 3
    @show.save!
  end

  test "should get create" do
    before = Admin::MaintenanceDebt.count
    get :create, {format: @show.id}
    assert_redirected_to admin_show_path(@show)
    change = @show.users.uniq.count
    assert_equal (before + change) , Admin::MaintenanceDebt.count
  end

end
