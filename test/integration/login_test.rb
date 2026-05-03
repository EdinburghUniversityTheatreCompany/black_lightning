require "test_helper"

class LoginTest < ActionDispatch::IntegrationTest
  test "shows error message with invalid credentials" do
    post user_session_path, params: { user: { email: "wrong@example.com", password: "wrongpassword" } }

    assert_response :unprocessable_entity
    assert_match "Invalid email or password.", response.body
  end

  test "user can log in with valid credentials" do
    password = "123Hel#2"
    admin = FactoryBot.create(:admin, email: "integration_test@example.com", password:)

    get new_user_session_path
    assert_response :success

    post user_session_path, params: { user: { email: admin.email, password: } }
    assert_redirected_to admin_path

    follow_redirect!

    assert_response :success
    assert_equal admin_path, path
    assert_match "Log Out", response.body
    assert_no_match "Log In", response.body
  end

  test "signing in after visiting a protected page redirects back to that page" do
    password = "123Hel#2"
    admin = FactoryBot.create(:admin, email: "admin_redirect_test@example.com", password:)

    get admin_staffings_path
    assert_redirected_to new_user_session_path

    follow_redirect!
    assert_response :success
    assert_match "You need to log in or register before continuing", response.body

    post user_session_path, params: { user: { email: admin.email, password: } }
    assert_redirected_to admin_staffings_path
  end
end
