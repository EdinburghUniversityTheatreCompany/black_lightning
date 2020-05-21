require 'test_helper'

class GetInvolvedControllerTest < ActionController::TestCase
  include SubpageHelper

  test 'should get index' do
    get :index
    assert_response :success
  end

  test 'should get index through page' do
    get :page
    check_if_overview
    get :page, params: { page: '' }
    check_if_overview
    get :page, params: { page: nil }
    check_if_overview
    get :page, params: { page: 'overview' }
    check_if_overview
  end

  test 'should get opportunities' do
    FactoryBot.create_list(:opportunity, 10)

    get :page, params: { page: 'opportunities' }
    assert_response :success
    assert_not_nil assigns(:opportunities)
  end

  test 'should get act' do
    get :page, params: { page: 'act' }
    assert_response :success
    assert_nil assigns(:opportunities)
  end

  test 'should get 404' do
    get :page, params: { page: 'finbar_the_viking' }
    assert_response 404
  end

  private

  def check_if_overview
    assert_response :success

    assert_equal '', assigns(:root_page)
    assert_equal get_subpages('get_involved', ''), assigns(:subpages)
  end
end
