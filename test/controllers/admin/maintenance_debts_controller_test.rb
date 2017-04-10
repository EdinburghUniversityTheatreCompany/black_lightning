require 'test_helper'

class Admin::MaintenanceDebtsControllerTest < ActionController::TestCase
  setup do
    @admin_maintenance_debt = admin_maintenance_debts(:one)
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
      post :create, admin_maintenance_debt: { dueBy: @admin_maintenance_debt.dueBy, show_id: @admin_maintenance_debt.show_id, user_id: @admin_maintenance_debt.user_id }
    end

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
    patch :update, id: @admin_maintenance_debt, admin_maintenance_debt: { dueBy: @admin_maintenance_debt.dueBy, show_id: @admin_maintenance_debt.show_id, user_id: @admin_maintenance_debt.user_id }
    assert_redirected_to admin_maintenance_debt_path(assigns(:admin_maintenance_debt))
  end

  test "should destroy admin_maintenance_debt" do
    assert_difference('Admin::MaintenanceDebt.count', -1) do
      delete :destroy, id: @admin_maintenance_debt
    end

    assert_redirected_to admin_maintenance_debts_path
  end
end
