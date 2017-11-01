require 'test_helper'

class Admin::MaintenanceDebtsControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryGirl.create(:admin)
    @user = FactoryGirl.create(:member)
    @show = FactoryGirl.create(:show)

    @admin_maintenance_debt = FactoryGirl.create(:maintenance_debt)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:admin_maintenance_debts)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create admin_maintenance_debt" do
    assert_difference('Admin::MaintenanceDebt.count') do
      post :create, admin_maintenance_debt: {due_by: Date.today, show_id: @show.id, user_id: @user.id}
    end
    assert(Admin::MaintenanceDebt.where(due_by: Date.today, show_id: @show.id, user_id: @user.id).any?, "there should be a debt with the details entered")

    assert_redirected_to admin_maintenance_debt_path(assigns(:admin_maintenance_debt))
  end

  test "should show admin_maintenance_debt" do
    get :show, id: @admin_maintenance_debt
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @admin_maintenance_debt
    assert_response :success
  end

  test "should update admin_maintenance_debt" do
    assert_no_difference('Admin::MaintenanceDebt.count') {
      patch :update, id: @admin_maintenance_debt, admin_maintenance_debt: {due_by: Date.today, show_id: @show.id, user_id: @user.id}
    }
    assert(Admin::MaintenanceDebt.where(due_by: Date.today, show_id: @show.id, user_id: @user.id).any?, "there should be a debt with the details entered")
    assert_redirected_to admin_maintenance_debt_path(assigns(:admin_maintenance_debt))
  end

  test "should destroy admin_maintenance_debt" do
    assert_difference('Admin::MaintenanceDebt.unfulfilled.count', -1) do
      assert_no_difference('Admin::MaintenanceDebt.count') do
        delete :destroy, id: @admin_maintenance_debt
      end
    end

    assert_redirected_to admin_maintenance_debts_path
  end

  test "should convert to staffing debt" do
    sdebt_count_before = Admin::StaffingDebt.count
    mdebt_count_before = Admin::MaintenanceDebt.unfulfilled.count
    assert_no_difference('Admin::MaintenanceDebt.count') do
      get :convert_to_staffing_debt, id: @admin_maintenance_debt.id
      assert(Admin::StaffingDebt.where(user_id: @admin_maintenance_debt.user_id, show_id: @admin_maintenance_debt.show_id).any?, "there should be a staffing debt with the same details as the old maintenance debt")
    end
    assert_redirected_to admin_maintenance_debts_path
    assert_equal (sdebt_count_before + 1), Admin::StaffingDebt.count
    assert_equal (mdebt_count_before + -1), Admin::MaintenanceDebt.unfulfilled.count
  end

end
