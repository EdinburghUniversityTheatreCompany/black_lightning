require 'test_helper'

class Admin::AnswersControllerTest < ActionController::TestCase
  test 'should download answer with file' do
    sign_in users(:admin)

    questionable = FactoryBot.create(:questionnaire)
    question = questionable.questions.first
    assert_not_nil question
    
    answer = FactoryBot.create(:answer, response_type: 'File', question: question, answerable: questionable)

    get :get_file, params: { id: answer }
    assert_response :success
  end

  test 'can access answer file when you can read the questionable' do
    other_user = FactoryBot.create(:user)

    questionnaire = FactoryBot.create(:questionnaire)
    user = questionnaire.show.users.first
    question = FactoryBot.create(:question, questionable: questionnaire, response_type: 'File', answered: true)
    answer = Admin::Answer.find_by_question_id(question.id)

    sign_in user

    get :get_file, params: { id: answer }
    assert_response :success

    sign_out user
    sign_in other_user

    get :get_file, params: { id: answer }
    assert_redirected_to access_denied_url
  end
end
