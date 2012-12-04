require 'test_helper'

class Admin::PermissionsControllerTest < ActionController::TestCase
  setup do
    @admin_permission = admin_permissions(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:admin_permissions)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create admin_permission" do
    assert_difference('Admin::Permission.count') do
      post :create, admin_permission: { action: @admin_permission.action, subject_class: @admin_permission.subject_class }
    end

    assert_redirected_to admin_permission_path(assigns(:admin_permission))
  end

  test "should show admin_permission" do
    get :show, id: @admin_permission
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @admin_permission
    assert_response :success
  end

  test "should update admin_permission" do
    put :update, id: @admin_permission, admin_permission: { action: @admin_permission.action, subject_class: @admin_permission.subject_class }
    assert_redirected_to admin_permission_path(assigns(:admin_permission))
  end

  test "should destroy admin_permission" do
    assert_difference('Admin::Permission.count', -1) do
      delete :destroy, id: @admin_permission
    end

    assert_redirected_to admin_permissions_path
  end
end
