require 'test_helper'

class Admin::HelpControllerTest < ActionController::TestCase
  setup do
    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
  end

  test "should get kramdown" do
    get :kramdown
    assert_response :success
  end

end
