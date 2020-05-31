require 'test_helper'

class AboutControllerTest < ActionController::TestCase
  include SubpageHelper
  # Index is a special case and explicitly routed to correspond to /about/.
  test 'should get index' do
    get :index
    check_if_overview
  end

  test 'should get index through page' do
    get :page
    check_if_overview
    get :page, params: { page: nil }
    check_if_overview
    get :page, params: { page: '' }
    check_if_overview
    get :page, params: { page: 'overview' }
    check_if_overview
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

  private

  def check_if_overview
    assert_response :success

    assert_equal '', assigns(:root_page)
    assert_equal get_subpages('about', ''), assigns(:subpages)
  end
end
