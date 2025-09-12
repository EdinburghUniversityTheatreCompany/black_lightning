require "test_helper"

# This is an integration test because it needs to follow redirects. It only tests the tests controller (which makes heavy use of the application_controller.)
class Admin::TestControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin)
  end

  test "index" do
    get admin_tests_path

    assert_response :success
  end

  test "test alerts" do
    get admin_tests_test_alerts_path(type: "all")

    assert_redirected_to admin_tests_path
    follow_redirect!

    assert_match "This is an error message.", response.body
    assert_match "This is another error message.", response.body
    assert_match "This is an alert message that should be added to the errors", response.body
    assert_match "This is a warning message.", response.body
    assert_match "This is a success message.", response.body
    assert_match "This is an info message.", response.body
    assert_match "This is a notice message that should be added to the success messages", response.body
  end

  test "alerts merge into error flash" do
    get admin_tests_test_alerts_path(type: "error")

    assert_redirected_to admin_tests_path
    follow_redirect!

    assert_nil flash[:alerts]
    assert_includes flash[:error], "This is an error message."
    assert_includes flash[:error], "This is an alert message that should be added to the errors"
  end

  test "notices merge into success flash" do
    get admin_tests_test_alerts_path(type: "success")

    assert_redirected_to admin_tests_path
    follow_redirect!

    assert_nil flash[:notices]
    assert_includes flash[:success], "This is a success message."
    assert_includes flash[:success], "This is a notice message that should be added to the success messages."
  end

  test "report 500 as admin" do
    get admin_tests_test_500_path

    assert_response 500
    assert_match "We have been informed.", response.body
    assert_nil flash[:error], "The error flash was not cleared"
    assert_match "<ul><li>This is a test server error.</li><li>This is a bonus error.</li></ul>", response.body, "The error page was not rendered using the template"
    assert_match "This is a bonus success.", response.body, "The success was not rendered"
    assert_match "Backtrace:", response.body, "The backtrace was not rendered for the admin"
  end

  test "report 404" do
    get admin_tests_test_404_path

    assert_response 404
    assert_nil flash[:error]
    assert_match "<ul><li>This is a test not found error.</li></ul>", response.body
  end

  test "report access denied" do
    get admin_tests_test_access_denied_path

    assert_response :forbidden
    assert_nil flash[:error]
    assert_match "<ul><li>You are not authorized to access this page.</li></ul>", response.body
  end
end
