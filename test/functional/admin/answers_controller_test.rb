require 'test_helper'

class Admin::AnswersControllerTest < ActionController::TestCase
  test 'should download answer with file' do
    sign_in users(:admin)

    question = FactoryBot.create(:question, response_type: 'File')
    answer = FactoryBot.create(:answer, question: question)

    get :get_file, params: { id: answer }
  
    assert_response :success

    assert_equal 'application/pdf', response.headers["Content-Type"]
    assert_equal "attachment; test.pdf", response.headers["Content-Disposition"]
  end

  test 'cannot download file for answer without file attached' do
    sign_in users(:admin)

    question = FactoryBot.create(:question, response_type: 'Long Text')
    answer = FactoryBot.create(:answer, question: question)

    get :get_file, params: { id: answer }

    assert_response 404
  end

  test 'can access answer file when you can read the questionable' do
    questionnaire = FactoryBot.create(:questionnaire)
    user = questionnaire.show.users.first
    question = FactoryBot.create(:question, questionable: questionnaire, response_type: 'File', answered: true)
    answer = Admin::Answer.find_by_question_id(question.id)

    sign_in user

    get :get_file, params: { id: answer }
    assert_response :success
  end

  test 'cannot access answer file when you cannot read the questionable' do
    question = FactoryBot.create(:question, response_type: 'File', answered: true)
    answer = Admin::Answer.find_by_question_id(question.id)

    sign_in users(:user)

    get :get_file, params: { id: answer }
    assert_redirected_to access_denied_url
  end
end
