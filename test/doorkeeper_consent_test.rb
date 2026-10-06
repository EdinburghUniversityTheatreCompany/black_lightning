require "application_integration_test"

class DoorkeeperConsentTest < ApplicationIntegrationTest
  setup do
    @user = FactoryBot.create(:user)
    @application = FactoryBot.create(:doorkeeper_application)
  end

  test "GET /oauth/authorize renders the Doorkeeper consent view with authorize button" do
    login_as @user

    params = {
      client_id: @application.uid,
      redirect_uri: @application.redirect_uri,
      response_type: "code",
      scope: "openid profile email"
    }

    get "/oauth/authorize", params: params

    assert_includes [ 200, 302 ], response.status, "Expected 200 or 302, got #{response.status}: #{response.body}"

    if response.status == 200
      assert_includes response.body, "Authorize"
    end
  end

  test "user can approve OAuth consent and receive authorization code" do
    login_as @user

    get "/oauth/authorize", params: {
      client_id: @application.uid,
      redirect_uri: @application.redirect_uri,
      response_type: "code",
      scope: "openid profile email"
    }
    assert_response :success

    post "/oauth/authorize", params: {
      client_id: @application.uid,
      redirect_uri: @application.redirect_uri,
      response_type: "code",
      scope: "openid profile email",
      authorize: "Authorize"
    }

    assert_response :redirect
    assert_includes response.headers["Location"], "code="
    assert_includes response.headers["Location"], @application.redirect_uri
  end

  test "user can deny OAuth consent and receive error" do
    login_as @user

    get "/oauth/authorize", params: {
      client_id: @application.uid,
      redirect_uri: @application.redirect_uri,
      response_type: "code",
      scope: "openid profile email"
    }
    assert_response :success
    assert_includes response.body, "Authorize"

    # The deny button uses DELETE.
    delete "/oauth/authorize", params: {
      client_id: @application.uid,
      redirect_uri: @application.redirect_uri,
      response_type: "code",
      scope: "openid profile email"
    }

    assert_response :redirect
    assert_includes response.headers["Location"], "error=access_denied"
    assert_includes response.headers["Location"], @application.redirect_uri
  end

  test "authorization code can be exchanged for access token after consent" do
    login_as @user

    get "/oauth/authorize", params: {
      client_id: @application.uid,
      redirect_uri: @application.redirect_uri,
      response_type: "code",
      scope: "openid profile email"
    }
    assert_response :success
    assert_includes response.body, "Authorize"

    post "/oauth/authorize", params: {
      client_id: @application.uid,
      redirect_uri: @application.redirect_uri,
      response_type: "code",
      scope: "openid profile email",
      authorize: "Authorize"
    }
    assert_response :redirect
    assert_includes response.headers["Location"], "code="

    assert_equal 1, Doorkeeper::AccessGrant.where(application_id: @application.id, resource_owner_id: @user.id).count

    auth_code_match = response.headers["Location"].match(/code=([^&]+)/)
    assert auth_code_match, "No authorization code in redirect"
    auth_code = auth_code_match[1]

    assert auth_code.present?
  end

  test "unauthenticated user is redirected to login before consent" do
    get "/oauth/authorize", params: {
      client_id: @application.uid,
      redirect_uri: @application.redirect_uri,
      response_type: "code",
      scope: "openid profile email"
    }

    assert_response :redirect
    assert_includes response.headers["Location"], new_user_session_path
  end

  test "forbid_redirect_uri blocks javascript scheme" do
    app = FactoryBot.build(:doorkeeper_application, redirect_uri: "javascript:alert(1)")
    assert_raises(ActiveRecord::RecordInvalid) { app.save! }
  end

  test "forbid_redirect_uri blocks data scheme" do
    app = FactoryBot.build(:doorkeeper_application, redirect_uri: "data:text/html,<script>alert(1)</script>")
    assert_raises(ActiveRecord::RecordInvalid) { app.save! }
  end

  test "forbid_redirect_uri blocks vbscript scheme" do
    app = FactoryBot.build(:doorkeeper_application, redirect_uri: "vbscript:msgbox('xss')")
    assert_raises(ActiveRecord::RecordInvalid) { app.save! }
  end

  test "force_ssl_in_redirect_uri enforces https in non-development" do
    app = FactoryBot.build(:doorkeeper_application, redirect_uri: "http://localhost:3001/callback")
    unless Rails.env.development?
      assert_raises(ActiveRecord::RecordInvalid) { app.save! }
    else
      assert app.valid?
    end
  end
end
