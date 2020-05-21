require 'test_helper'

class Admin::ResourcesControllerTest < ActionController::TestCase
  include SubpageHelper

  setup do
    sign_in users(:admin)
  end

  # This test will only work properly if the helper test 'get subpages at roots' succeeds.
  test 'should get overview' do
    get :index
    check_if_overview
    get :page, params: { page: 'overview' }
    check_if_overview
    get :page, params: { page: '' }
    check_if_overview
    get :page, params: { page: nil }
    check_if_overview
    get :page
    check_if_overview
  end

  test 'should get tech resources' do
    assert_routing 'admin/resources/tech', controller: 'admin/resources', action: 'page', page: 'tech'

    get :page, params: { page: 'tech' }
    assert_response :success

    assert_equal 'tech', assigns(:root_page)
    assert_equal get_subpages('admin/resources', 'tech'), assigns(:subpages)
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
    assert_equal get_subpages('admin/resources', ''), assigns(:subpages)
  end
end
