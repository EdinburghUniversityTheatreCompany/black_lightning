require 'test_helper'

class Archives::ProposalsControllerTest < ActionController::TestCase
  test 'index' do
    sign_in users(:admin)

    FactoryBot.create_list(:proposal, 10)

    get :index
    assert_response :success

    get :index, params: { commit: 'Random' }
    assert_response 302
  end
end
