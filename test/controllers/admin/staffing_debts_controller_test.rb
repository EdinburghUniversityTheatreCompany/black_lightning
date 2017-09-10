require 'test_helper'

class Admin::StaffingDebtsControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryGirl.create(:admin)
    @admin_staffing_debt = FactoryGirl.create(:staffing_debt)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:sdebts)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create admin_staffing_debt" do
    assert_difference('Admin::StaffingDebt.count') do
      post :create, admin_staffing_debt: { admin_staffing_job_id: @admin_staffing_debt.admin_staffing_job_id, due_by: @admin_staffing_debt.due_by, show_id: @admin_staffing_debt.show_id, user_id: @admin_staffing_debt.user_id }
    end

    assert_redirected_to admin_staffing_debts_path
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
    patch :update, id: @admin_staffing_debt, admin_staffing_debt: { admin_staffing_job_id: @admin_staffing_debt.admin_staffing_job_id, due_by: @admin_staffing_debt.due_by, show_id: @admin_staffing_debt.show_id, user_id: @admin_staffing_debt.user_id }
    assert_redirected_to admin_staffing_debts_path
  end

  test "should destroy admin_staffing_debt" do
    assert_difference('Admin::StaffingDebt.count', -1) do
      delete :destroy, id: @admin_staffing_debt
    end

    assert_redirected_to admin_staffing_debts_path
  end
end