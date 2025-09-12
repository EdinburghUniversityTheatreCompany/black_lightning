require "test_helper"

class TestsControllerTest < ActionController::TestCase
    test "report 500 as not signed in user" do
        get :test_500

        assert_response 500

        assert_match "We have been informed.", response.body
        assert_match "This is a test server error.", response.body
        assert_no_match "Backtrace", response.body, "The backtrace was rendered for the non-admin"
    end
end
