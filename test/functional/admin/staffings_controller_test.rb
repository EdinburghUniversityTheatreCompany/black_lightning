require 'test_helper'

class Admin::StaffingsControllerTest < ActionController::TestCase
  setup do
    @admin_staffing = admin_staffings(:one)
    
    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:admin_staffings)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create admin_staffing" do
    assert_difference('Admin::Staffing.count') do
      post :create, admin_staffing: { date: @admin_staffing.date, show_title: @admin_staffing.show_title }
    end

    assert_redirected_to admin_staffing_path(assigns(:admin_staffing))
  end

  test "should show admin_staffing" do
    get :show, id: @admin_staffing
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @admin_staffing
    assert_response :success
  end

  test "should update admin_staffing" do
    put :update, id: @admin_staffing, admin_staffing: { date: @admin_staffing.date, show_title: @admin_staffing.show_title }
    assert_redirected_to admin_staffing_path(assigns(:admin_staffing))
  end

  test "should destroy admin_staffing" do
    assert_difference('Admin::Staffing.count', -1) do
      delete :destroy, id: @admin_staffing
    end

    assert_redirected_to admin_staffings_path
  end
end
