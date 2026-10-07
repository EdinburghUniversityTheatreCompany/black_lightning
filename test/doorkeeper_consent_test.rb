require "application_integration_test"

class DoorkeeperConsentTest < ApplicationIntegrationTest
  setup do
    @user = FactoryBot.create(:user)
    @application = FactoryBot.create(:doorkeeper_application)
  end

  test "approving consent issues an authorization code" do
    login_as @user
    get "/oauth/authorize", params: authorize_params
    assert_response :success
    assert_includes response.body, "Authorize"

    post "/oauth/authorize", params: authorize_params.merge(authorize: "Authorize")

    assert_response :redirect
    assert_includes response.location, "#{@application.redirect_uri}?code="
    assert_equal 1, Doorkeeper::AccessGrant.where(application_id: @application.id, resource_owner_id: @user.id).count
  end

  test "denying consent redirects with access_denied" do
    login_as @user
    # The deny button uses DELETE.
    delete "/oauth/authorize", params: authorize_params

    assert_response :redirect
    assert_includes response.location, "error=access_denied"
  end

  test "an unauthenticated user is sent to log in before consent" do
    get "/oauth/authorize", params: authorize_params

    assert_response :redirect
    assert_includes response.location, new_user_session_path
  end

  test "script schemes and plain http are refused as redirect URIs" do
    [ "javascript:alert(1)", "data:text/html,<script>alert(1)</script>", "vbscript:msgbox('xss')", "http://localhost:3001/callback" ].each do |uri|
      assert_not FactoryBot.build(:doorkeeper_application, redirect_uri: uri).valid?, uri
    end
  end

  private

  def authorize_params
    { client_id: @application.uid, redirect_uri: @application.redirect_uri, response_type: "code", scope: "openid profile email" }
  end
end
