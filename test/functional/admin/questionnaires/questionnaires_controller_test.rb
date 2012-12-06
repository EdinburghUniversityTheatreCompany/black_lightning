require 'test_helper'

class Admin::Questionnaires::QuestionnairesControllerTest < ActionController::TestCase

  setup do
    @admin_questionnaires_questionnaire = admin_questionnaires_questionnaires(:one)

    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:admin_questionnaires_questionnaires)
  end

  test "should show admin_questionnaires_questionnaire" do
    get :show,  id: @admin_questionnaires_questionnaire
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @admin_questionnaires_questionnaire
    assert_response :success
  end

  test "should update admin_questionnaires_questionnaire" do
    team_user = User.find_by_email('test@bedlamtheatre.co.uk')

    put :update, id: @admin_questionnaires_questionnaire, admin_questionnaires_questionnaire: { :questions_attributes => { '0' => { :question_text => 'Testing', :response_type => "Long Text"} } }
    assert_redirected_to admin_questionnaires_questionnaire_path(1, assigns(:questionnaire))
  end

  test "should destroy admin_questionnaires_questionnaire" do
    assert_difference('Admin::Questionnaires::Questionnaire.count', -1) do
      delete :destroy, id: @admin_questionnaires_questionnaire
    end

    assert_redirected_to admin_questionnaires_questionnaires_path
  end
end
