require "test_helper"

class Display::SetupControllerTest < ActionController::TestCase
  test "lists every display url with a suggested duration" do
    get :show

    assert_response :success
    assert_match "/display/whats-on", response.body
    assert_match "/display/next/6", response.body
    assert_match "/display/on-this-day", response.body
  end
end
