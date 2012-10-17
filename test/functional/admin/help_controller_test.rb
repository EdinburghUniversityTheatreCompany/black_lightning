require 'test_helper'

class Admin::HelpControllerTest < ActionController::TestCase
  setup do
    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
  end

  test "should get markdown" do
    get :markdown
    assert_response :success
  end

end
