require 'test_helper'

class Admin::TechieFamiliesControllerTest < ActionController::TestCase
  setup do
    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
  end

  test "should get index" do
    get :index
    assert_response :success
  end

end
