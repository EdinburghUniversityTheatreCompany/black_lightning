require 'test_helper'

class Admin::StaffingDebtsControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryBot.create(:admin)
    @admin_staffing_debt = FactoryBot.create(:staffing_debt)
    @show = FactoryBot.create(:show)
    @user = FactoryBot.create(:member)
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
      post :create, admin_staffing_debt: {due_by: Date.today, show_id: @show.id, user_id: @user.id}
    end
    assert(Admin::StaffingDebt.where(due_by: Date.today, show_id: @show.id, user_id: @user.id).any?, "there should be a debt with the details entered")

    assert_redirected_to admin_staffing_debts_path
  end

  test "should show admin_staffing_debt" do
    get :show, params: { id: @admin_staffing_debt}
    assert_response :success
  end

  test "should get edit" do
    get :edit, params: { id: @admin_staffing_debt}
    assert_response :success
  end

  test "should update admin_staffing_debt" do
    assert_no_difference('Admin::StaffingDebt.count') do
      patch :update, params: {id: @admin_staffing_debt, admin_staffing_debt: {due_by: Date.today, show_id: @show.id, user_id: @user.id}}
    end

    assert(Admin::StaffingDebt.where(due_by: Date.today, show_id: @show.id, user_id: @user.id).any?, "there should be a debt with the details entered")
    assert_redirected_to admin_staffing_debts_path
  end

  test "should destroy admin_staffing_debt" do
    assert_difference('Admin::StaffingDebt.unfulfilled.count', -1) do
      assert_no_difference('Admin::StaffingDebt.count') do
        delete :destroy, params: { id: @admin_staffing_debt}
      end
    end

    assert_redirected_to admin_staffing_debts_path
  end

end
