require 'test_helper'

class AdminControllerTest < ActionController::TestCase

  test "should get index" do
    sign_in FactoryGirl.create(:admin)

    get :index
    assert_response :success
  end

end
