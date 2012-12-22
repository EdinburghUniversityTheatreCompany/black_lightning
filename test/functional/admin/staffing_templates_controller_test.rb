require 'test_helper'

class Admin::StaffingTemplatesControllerTest < ActionController::TestCase
  setup do
    @admin_staffing_template = admin_staffing_templates(:one)
    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
  end

  test "should get index" do
    get :index
    assert_response :success
  end

  test "should get show" do
    get :show, id: @admin_staffing_template
    assert_response :success
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create staffing_template" do
    assert_difference('Admin::StaffingTemplate.count') do
      post :create, admin_staffing_template: { name: @admin_staffing_template.name }
    end

    assert_redirected_to admin_staffing_template_path(assigns(:template))
  end

  test "should get edit" do
    get :edit, id: @admin_staffing_template
    assert_response :success
  end

  test "should update staffing_template" do
    put :update, id: @admin_staffing_template, admin_staffing_template: { name: @admin_staffing_template.name }
    assert_redirected_to admin_staffing_template_path(@admin_staffing_template)
  end

  test "should destroy staffing_template" do
    assert_difference('Admin::StaffingTemplate.count', -1) do
      delete :destroy, id: @admin_staffing_template
    end

    assert_redirected_to admin_staffing_templates_path
  end
end
