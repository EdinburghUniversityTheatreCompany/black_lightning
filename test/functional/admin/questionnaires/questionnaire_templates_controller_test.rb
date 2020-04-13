require 'test_helper'

class Admin::Questionnaires::QuestionnaireTemplatesControllerTest < ActionController::TestCase
  setup do
    @template = admin_questionnaires_questionnaire_templates(:one)

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

  test 'should create admin_questionnaires_questionnaire_template' do
    # Remove the existing entry:
    Admin::Questionnaires::QuestionnaireTemplate.find(@template.id).destroy

    assert_difference('Admin::Questionnaires::QuestionnaireTemplate.count') do
      post :create, params:{admin_questionnaires_questionnaire_template: { name: @template.name }}
    end

    assert_redirected_to admin_questionnaires_questionnaire_template_path(assigns(:template))
  end

  test 'should show admin_questionnaires_questionnaire_template' do
    get :show, params: { id: @template}
    assert_response :success
  end

  test 'should get edit' do
    get :edit, params: { id: @template}
    assert_response :success
  end

  test 'should update admin_questionnaires_questionnaire_template' do
    put :update, params: {id: @template, admin_questionnaires_questionnaire_template: { name: @template.name }}
    assert_redirected_to admin_questionnaires_questionnaire_template_path(assigns(:template))
  end

  test 'should destroy admin_questionnaires_questionnaire_template' do
    assert_difference('Admin::Questionnaires::QuestionnaireTemplate.count', -1) do
      delete :destroy, params: { id: @template}
    end

    assert_redirected_to admin_questionnaires_questionnaire_templates_path
  end
end
