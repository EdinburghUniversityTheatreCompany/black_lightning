require 'test_helper'

class Admin::Proposals::CallsControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryGirl.create(:admin)
  end

  test "should get index" do
    FactoryGirl.create_list(:proposal_call, 10)

    get :index
    assert_response :success
    assert_not_nil assigns(:admin_proposals_calls)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create admin_proposals_call" do
    attrs = FactoryGirl.attributes_for(:proposal_call, question_count: 5)

    assert_difference('Admin::Proposals::Call.count') do
      post :create, admin_proposals_call: attrs
    end

    assert_redirected_to admin_proposals_call_path(assigns(:admin_proposals_call))
  end

  test "should show admin_proposals_call" do
    @call = FactoryGirl.create(:proposal_call, question_count: 5, proposal_count: 5)

    get :show, id: @call
    assert_response :success
  end

  test "should get edit" do
    @call = FactoryGirl.create(:proposal_call, question_count: 5)

    get :edit, id: @call
    assert_response :success
  end

  test "should update admin_proposals_call" do
    attrs = FactoryGirl.attributes_for(:proposal_call, question_count: 3)
    @call = FactoryGirl.create(:proposal_call, question_count: 5, proposal_count: 5)

    put :update, id: @call, admin_proposals_call: attrs
    assert_redirected_to admin_proposals_call_path(assigns(:admin_proposals_call))
  end

  test "should destroy admin_proposals_call" do
    @call = FactoryGirl.create(:proposal_call)

    assert_difference('Admin::Proposals::Call.count', -1) do
      delete :destroy, id: @call
    end

    assert_redirected_to admin_proposals_calls_path
  end
end
