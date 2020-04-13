require 'test_helper'

class Admin::Proposals::CallQuestionTemplatesControllerTest < ActionController::TestCase
  setup do
    @template = admin_proposals_call_question_templates(:one)

    sign_in FactoryBot.create(:admin)
  end

  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:templates)
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create admin_proposals_call_question_template' do
    # Remove the existing entry:
    Admin::Proposals::CallQuestionTemplate.find(@template.id).destroy

    assert_difference('Admin::Proposals::CallQuestionTemplate.count') do
      post :create, params: {admin_proposals_call_question_template: { name: @template.name }}
    end

    assert_redirected_to admin_proposals_call_question_template_path(assigns(:template))
  end

  test 'should get edit' do
    get :edit, params: { id: @template}
    assert_response :success
  end

  test 'should update admin_proposals_call_question_template' do
    put :update, params: {id: @template, admin_proposals_call_question_template: { name: @template.name }}
    assert_redirected_to edit_admin_proposals_call_question_template_path(assigns(:template))
  end

  test 'should destroy admin_proposals_call_question_template' do
    assert_difference('Admin::Proposals::CallQuestionTemplate.count', -1) do
      delete :destroy, params: { id: @template}
    end

    assert_redirected_to admin_proposals_call_question_templates_path
  end
end
