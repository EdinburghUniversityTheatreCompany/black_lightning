require 'test_helper'

class ArchivesControllerTest < ActionController::TestCase
  test 'should get index' do
    get :index
    assert_response :success
  end

  test 'should get page' do
    get :page, params: { page: 'help' }
    assert_response :success
  end
end