require 'test_helper'

class Admin::PermissionsControllerTest < ActionController::TestCase
  setup do
    @admin_permission = admin_permissions(:one)

    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
  end

  test "should get grid" do
    get :grid
    assert_response :success
  end

end
