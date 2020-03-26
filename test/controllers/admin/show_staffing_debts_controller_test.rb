require 'test_helper'

class Admin::ShowStaffingDebtsControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryBot.create(:admin)
    @show = FactoryBot.create(:show)
    @show.staffing_debt_start = Date.today + 3
    @show.save!
  end

  test "should get create" do
    before = Admin::StaffingDebt.count
    get :create, params: {format:@show.id, number_of_slots_due: 1}
    assert_redirected_to admin_show_path(@show)
    change = @show.users.uniq.count
    assert_equal (before + change) , Admin::StaffingDebt.count
    get :create, {format:@show.id, number_of_slots_due: 2}
    assert_equal (before + (change *2)) , Admin::StaffingDebt.count
  end

  test "should get update" do
    #get :update
    #assert_response :success
  end

end
