require 'test_helper'

class Archives::ShowsControllerTest < ActionController::TestCase
  test "should get index" do
    get :index
    assert_response :success
  end
end
