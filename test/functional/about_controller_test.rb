require 'test_helper'

class AboutControllerTest < ActionController::TestCase
  # Index is a special case and explicitly routed to correspond to /about/.
  test 'should get index' do
    get :index
    assert_response :success
  end

  # Test if getting an existing page works.
  test 'should get environmental resources' do
    get :page, params: { page: 'environmental/resources' }
    assert_response :success
  end

  # Test if getting a non-existent page gives a 404.
  test 'should not get non-existent page' do
    get :page, params: { page: 'this/page/does/not/exist/I/think' }
    assert_response :missing
  end
end
