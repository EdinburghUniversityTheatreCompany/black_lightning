require "test_helper"

class ApplicationControllerTest < ActionController::TestCase
  tests ShowsController
  # The Shows Controller is a pretty simple controller, so, we can use it as a base without the controller influencing much.

  test "access denied" do
    show = FactoryBot.create(:show, is_public: false)
    get :show, params: { id: show.slug }
    assert_response 403
  end

  test "set globals" do
    get :index

    assert_equal "it@bedlamtheatre.co.uk", assigns(:support_email)
    assert_equal "http://test.host", assigns(:base_url)
    assert_equal "http://test.host/shows", assigns(:meta)["og:url"]
    assert_equal [ :description, "og:url", "og:image", "og:title", "viewport", "og:description" ], assigns(:meta).keys
  end

  # ==================
  # Profile completion blocking tests
  # ==================

  test "unauthenticated users are not blocked by profile completion" do
    get :index

    assert_response :success
  end

  test "authenticated users with complete profiles are not blocked" do
    complete_user = FactoryBot.create(:user, profile_completed_at: Time.current)
    sign_in complete_user

    get :index

    assert_response :success
  end

  test "authenticated users with incomplete profiles are redirected to profile completion" do
    incomplete_user = FactoryBot.create(:user, profile_completed_at: nil)
    sign_in incomplete_user

    get :index

    assert_redirected_to profile_completion_path
    assert_includes flash[:notice], "Please complete your profile to continue."
  end
end
