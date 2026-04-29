require "test_helper"

class Admin::HelpControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
  end

  test "should get venue location" do
    get :venue_location
    assert_response :success
  end
end
