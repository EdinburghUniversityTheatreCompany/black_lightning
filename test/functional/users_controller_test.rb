require "test_helper"

class UsersControllerTest < ActionController::TestCase
  test "should get show for public profile" do
    user = FactoryBot.create(:user, public_profile: true)

    get :show, params: { id: user }

    assert_response :success
    assert_equal user.team_memberships(true), assigns(:team_memberships)
  end

  test "a position on the projects grid is escaped, not run as markup" do
    user = FactoryBot.create(:user, public_profile: true)
    # is_public: the profile lists public shows only, and the factory picks it at random.
    show = FactoryBot.create(:show, is_public: true)
    FactoryBot.create(:team_member, user: user, teamwork: show, position: "<script>alert(1)</script>")

    get :show, params: { id: user }

    assert_response :success
    assert_includes response.body, "<b>Position</b>: &lt;script&gt;alert(1)&lt;/script&gt;"
    assert_not_includes response.body, "<script>alert(1)</script>"
  end

  test "should get access_denied for private profile" do
    user = users(:admin)

    get :show, params: { id: user }

    assert_response 403
  end

  test "consent for self" do
    user = users(:user)

    sign_in user

    put :consent, params: { id: user }

    assert_redirected_to admin_path

    assert_equal Date.current, User.find(user.id).consented
  end
end
