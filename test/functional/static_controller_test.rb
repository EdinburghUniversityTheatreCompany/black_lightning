require 'test_helper'

class StaticControllerTest < ActionController::TestCase
  include ActionDispatch::Routing::UrlFor
  test 'should get home' do
    FactoryBot.create_list(:show, 10)

    get :home
    assert_response :success
  end

  test 'should get contact' do
    get :show, params: { page: 'contact' }
    assert_response :success
  end

  test 'should get 404 when navigating to nonexistent page' do
    get :show, params: { page: 'pineapples_and_the_hexagon_a_memoir' }
    assert_response 404
  end
end
