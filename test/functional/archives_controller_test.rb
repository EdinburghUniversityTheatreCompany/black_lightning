require 'test_helper'

class ArchivesControllerTest < ActionController::TestCase
  test 'should get index' do
    get :index
    assert_response :success
  end
end
