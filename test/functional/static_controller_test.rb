require 'test_helper'

class StaticControllerTest < ActionController::TestCase
  test 'should get home' do
    FactoryBot.create_list(:show, 10)

    get :home
    assert_response :success
  end

  test 'should get 403' do
    get :access_denied
    assert_response 403
  end

  test 'should get 404' do
    get :render_404
    assert_response 404
  end

  test 'should get 500' do
    get :render_500
    assert_response 500
  end
end
