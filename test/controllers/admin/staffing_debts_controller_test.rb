require 'test_helper'

class Admin::StaffingDebtsControllerTest < ActionController::TestCase
  setup do
    @admin_staffing_debt = admin_staffing_debts(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:admin_staffing_debts)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create admin_staffing_debt" do
    assert_difference('Admin::StaffingDebt.count') do
      post :create, admin_staffing_debt: { admin_staffing_job_id: @admin_staffing_debt.admin_staffing_job_id, dueBy: @admin_staffing_debt.dueBy, show_id: @admin_staffing_debt.show_id, user_id: @admin_staffing_debt.user_id }
    end

    assert_redirected_to admin_staffing_debt_path(assigns(:admin_staffing_debt))
  end

  test "should show admin_staffing_debt" do
    get :show, id: @admin_staffing_debt
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @admin_staffing_debt
    assert_response :success
  end

  test "should update admin_staffing_debt" do
    patch :update, id: @admin_staffing_debt, admin_staffing_debt: { admin_staffing_job_id: @admin_staffing_debt.admin_staffing_job_id, dueBy: @admin_staffing_debt.dueBy, show_id: @admin_staffing_debt.show_id, user_id: @admin_staffing_debt.user_id }
    assert_redirected_to admin_staffing_debt_path(assigns(:admin_staffing_debt))
  end

  test "should destroy admin_staffing_debt" do
    assert_difference('Admin::StaffingDebt.count', -1) do
      delete :destroy, id: @admin_staffing_debt
    end

    assert_redirected_to admin_staffing_debts_path
  end
end
