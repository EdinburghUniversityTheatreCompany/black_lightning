require 'test_helper'

class Admin::Proposals::CallQuestionTemplatesControllerTest < ActionController::TestCase
  setup do
    @admin_proposals_call_question_template = admin_proposals_call_question_templates(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:admin_proposals_call_question_templates)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create admin_proposals_call_question_template" do
    assert_difference('Admin::Proposals::CallQuestionTemplate.count') do
      post :create, admin_proposals_call_question_template: {  }
    end

    assert_redirected_to admin_proposals_call_question_template_path(assigns(:admin_proposals_call_question_template))
  end

  test "should show admin_proposals_call_question_template" do
    get :show, id: @admin_proposals_call_question_template
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @admin_proposals_call_question_template
    assert_response :success
  end

  test "should update admin_proposals_call_question_template" do
    put :update, id: @admin_proposals_call_question_template, admin_proposals_call_question_template: {  }
    assert_redirected_to admin_proposals_call_question_template_path(assigns(:admin_proposals_call_question_template))
  end

  test "should destroy admin_proposals_call_question_template" do
    assert_difference('Admin::Proposals::CallQuestionTemplate.count', -1) do
      delete :destroy, id: @admin_proposals_call_question_template
    end

    assert_redirected_to admin_proposals_call_question_templates_path
  end
end
