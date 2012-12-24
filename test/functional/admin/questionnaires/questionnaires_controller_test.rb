require 'test_helper'

class Admin::Questionnaires::QuestionnairesControllerTest < ActionController::TestCase

  setup do
    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
  end

  test "should get index" do
    FactoryGirl.create_list(:questionnaire, 10)

    get :index
    assert_response :success
    assert_not_nil assigns(:admin_questionnaires_questionnaires)
  end

  test "should show admin_questionnaires_questionnaire" do
    @questionnaire = FactoryGirl.create(:questionnaire)

    get :show,  id: @questionnaire
    assert_response :success
  end

  test "should get edit" do
    @questionnaire = FactoryGirl.create(:questionnaire)

    get :edit, id: @questionnaire
    assert_response :success
  end

  test "should update admin_questionnaires_questionnaire" do
    @questionnaire = FactoryGirl.create(:questionnaire)

    team_user = User.find_by_email('test@bedlamtheatre.co.uk')

    put :update, id: @questionnaire, admin_questionnaires_questionnaire: { :questions_attributes => { '0' => { :question_text => 'Testing', :response_type => "Long Text"} } }
    assert_redirected_to admin_questionnaires_questionnaire_path(@questionnaire, assigns(:questionnaire))
  end

  test "should destroy admin_questionnaires_questionnaire" do
    @questionnaire = FactoryGirl.create(:questionnaire)

    assert_difference('Admin::Questionnaires::Questionnaire.count', -1) do
      delete :destroy, id: @questionnaire
    end

    assert_redirected_to admin_questionnaires_questionnaires_path
  end
end
