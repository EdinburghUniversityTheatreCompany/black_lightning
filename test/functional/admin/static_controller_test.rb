require "test_helper"

class Admin::StaticControllerTest < ActionController::TestCase
  test "committee can get committee" do
    sign_in users(:committee)

    get :committee
    assert_response :success
  end

  test "non committee cannot get committee" do
    sign_in users(:member)

    get :committee
    assert_response :forbidden
  end

  test "the page is gated by the grid permission, not the role name" do
    # A role that is not Committee but has been granted the permission gets in...
    user = users(:member)
    Role.create!(name: "Committee Aide").tap do |role|
      role.permissions << admin_permissions(:access_committee)
      user.add_role(role)
    end
    sign_in user

    get :committee
    assert_response :success
  end

  test "the Committee role without the permission is refused" do
    # ...and the role name alone grants nothing once the permission is unticked.
    roles(:committee).permissions.delete(admin_permissions(:access_committee))
    sign_in users(:committee)

    get :committee
    assert_response :forbidden
  end

  test "error static page" do
    sign_in users(:admin)

    get :error, params: { page: "pineapple" }
    assert_response 404
  end
end
