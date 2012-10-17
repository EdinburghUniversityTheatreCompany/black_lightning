require 'test_helper'

class AdminControllerTest < ActionController::TestCase
  test "unauthorised user should not get index" do
    get :index
    assert_response '403'
  end

end
