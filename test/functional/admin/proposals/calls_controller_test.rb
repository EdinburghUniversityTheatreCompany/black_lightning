require 'test_helper'

class Admin::Proposals::CallsControllerTest < ActionController::TestCase
  setup do
    @admin_proposals_call = admin_proposals_calls(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:admin_proposals_calls)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create admin_proposals_call" do
    assert_difference('Admin::Proposals::Call.count') do
      post :create, admin_proposals_call: { deadline: @admin_proposals_call.deadline, name: @admin_proposals_call.name, open: @admin_proposals_call.open }
    end

    assert_redirected_to admin_proposals_call_path(assigns(:admin_proposals_call))
  end

  test "should show admin_proposals_call" do
    get :show, id: @admin_proposals_call
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @admin_proposals_call
    assert_response :success
  end

  test "should update admin_proposals_call" do
    put :update, id: @admin_proposals_call, admin_proposals_call: { deadline: @admin_proposals_call.deadline, name: @admin_proposals_call.name, open: @admin_proposals_call.open }
    assert_redirected_to admin_proposals_call_path(assigns(:admin_proposals_call))
  end

  test "should destroy admin_proposals_call" do
    assert_difference('Admin::Proposals::Call.count', -1) do
      delete :destroy, id: @admin_proposals_call
    end

    assert_redirected_to admin_proposals_calls_path
  end
end
