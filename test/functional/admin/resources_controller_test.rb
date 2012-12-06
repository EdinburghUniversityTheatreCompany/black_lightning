require 'test_helper'

class Admin::ResourcesControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
  end

  test "should get tech - lighting" do
    get "tech/lighting"
    assert_response :success
  end
end
