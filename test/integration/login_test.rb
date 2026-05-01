require "test_helper"

class LoginTest < ActionDispatch::IntegrationTest
  test "user can log in with valid credentials" do
    password = "123Hel#2"
    user = FactoryBot.create(:user, email: "integration_test@example.com", password:)

    get new_user_session_path
    assert_response :success

    post user_session_path, params: { user: { email: user.email, password: } }
    assert_redirected_to root_path

    follow_redirect!

    assert_response :success
    assert_equal root_path, path
    assert_match "Log Out", response.body
    assert_no_match "Log In", response.body
  end
end
