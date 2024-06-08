require 'test_helper'

class Admin::StaticControllerTest < ActionController::TestCase
  test 'committee can get committee' do
    sign_in users(:committee)
    
    get :committee
    assert_response :success
  end

  test 'non committee cannot get committee' do
    sign_in users(:member)

    get :committee
    assert_response :forbidden
  end

  test 'error static page' do
    sign_in users(:admin)

    get :error, params: { page: 'pineapple' }
    assert_response 404
  end
end
