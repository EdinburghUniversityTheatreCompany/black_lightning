require "test_helper"

class ApplicationControllerTest < ActionController::TestCase
  tests ShowsController
  # The Shows Controller is a pretty simple controller, so, we can use it as a base without the controller influencing much.

  test "access denied" do
    show = FactoryBot.create(:show, is_public: false)
    get :show, params: { id: show.slug }
    assert_response 403
  end

  # set_globals seeds only what cannot change during the action. og:url and og:title used to be
  # built here and both read @title, which the action assigns afterwards -- so og:title was
  # always nil. MetaHelper derives them at render time now; seo_metadata_test asserts the
  # rendered tags.
  test "set globals" do
    get :index

    assert_equal "it@bedlamtheatre.co.uk", assigns(:support_email)
    assert_equal "http://test.host", assigns(:base_url)
    assert_equal [ :description, "og:image", "viewport" ], assigns(:meta).keys
    assert_nil assigns(:meta)["og:title"], "og:title must be derived at render time, not here"
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
