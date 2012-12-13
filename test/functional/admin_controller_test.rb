require 'test_helper'

class AdminControllerTest < ActionController::TestCase

  test "should get index" do
    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user

    get :index
    assert_response :success
  end

end
