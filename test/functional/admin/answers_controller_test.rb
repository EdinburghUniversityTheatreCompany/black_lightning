require 'test_helper'

class Admin::AnswersControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryBot.create(:admin)
  end

  test 'should download answer with file' do
    answer = FactoryBot.create(:answer, response_type: 'File')

    get :get_file, params: {id: answer}
    assert_response :success
  end
end
