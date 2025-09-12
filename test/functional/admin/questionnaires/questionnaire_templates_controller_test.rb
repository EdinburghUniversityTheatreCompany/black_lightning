require "test_helper"

class Admin::Questionnaires::QuestionnaireTemplatesControllerTest < ActionController::TestCase
  setup do
    @template = admin_questionnaires_questionnaire_templates(:one)
    assert @template.questions.present?
    sign_in users(:admin)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:questionnaire_templates)
  end

  test "should show admin_questionnaires_questionnaire_template" do
    get :show, params: { id: @template }
    assert_response :success
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create admin_questionnaires_questionnaire_template" do
    assert_difference("Admin::Questionnaires::QuestionnaireTemplate.count") do
      post :create, params: { admin_questionnaires_questionnaire_template: { name: "Pineapple" } }
    end

    assert_redirected_to admin_questionnaires_questionnaire_template_path(assigns(:questionnaire_template))
  end

  test "should not create invalid admin_questionnaires_questionnaire_template" do
    assert_no_difference("Admin::Questionnaires::QuestionnaireTemplate.count") do
      post :create, params: { admin_questionnaires_questionnaire_template: { name: nil } }
    end

    assert_response :unprocessable_entity
  end

  test "should get edit" do
    get :edit, params: { id: @template }
    assert_response :success
  end

  test "should update admin_questionnaires_questionnaire_template" do
    put :update, params: { id: @template, admin_questionnaires_questionnaire_template: { name: "Finbar the Viking" } }

    assert Admin::Questionnaires::QuestionnaireTemplate.where(name: "Finbar the Viking").any?
    assert_redirected_to admin_questionnaires_questionnaire_template_path(assigns(:questionnaire_template))
  end

  test "should not update invalid admin_questionnaires_questionnaire_template" do
    put :update, params: { id: @template, admin_questionnaires_questionnaire_template: { name: nil } }

    assert Admin::Questionnaires::QuestionnaireTemplate.where(name: @template.name).any?
    assert_response :unprocessable_entity
  end

  test "should destroy admin_questionnaires_questionnaire_template" do
    assert_difference("Admin::Questionnaires::QuestionnaireTemplate.count", -1) do
      delete :destroy, params: { id: @template }
    end

    assert_redirected_to admin_questionnaires_questionnaire_templates_path
  end
end
