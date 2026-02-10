require "test_helper"

class DevAuthControllerTest < ActionDispatch::IntegrationTest
  setup do
    @claude_user = User.create!(
      email: "unknown_claude@bedlamtheatre.co.uk",
      password: SecureRandom.hex(20),
      first_name: "Claude",
      last_name: "Dev",
      consented: Time.current,
      profile_completed_at: Time.current
    )
  end

  test "signs in with correct token and redirects to root" do
    get dev_auth_login_path, params: { token: "claude-screenshot-token" }
    assert_redirected_to root_path
  end

  test "redirects to specified path" do
    get dev_auth_login_path, params: { token: "claude-screenshot-token", redirect_to: "/admin/shows" }
    assert_redirected_to "/admin/shows"
  end

  test "rejects invalid token" do
    get dev_auth_login_path, params: { token: "wrong" }
    assert_response :unauthorized
  end

  test "rejects missing token" do
    get dev_auth_login_path
    assert_response :unauthorized
  end

  test "returns 404 when dev user missing" do
    @claude_user.destroy
    get dev_auth_login_path, params: { token: "claude-screenshot-token" }
    assert_response :not_found
  end

  test "respects custom DEV_AUTH_TOKEN env var" do
    ENV["DEV_AUTH_TOKEN"] = "custom-token"
    get dev_auth_login_path, params: { token: "custom-token" }
    assert_redirected_to root_path
  ensure
    ENV.delete("DEV_AUTH_TOKEN")
  end
end
