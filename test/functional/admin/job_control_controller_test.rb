require 'test_helper'

class Admin::JobControlControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
  end

  test "should get overview" do
    get :overview
    assert_response :success
  end

  test "should get working" do
    get :working
    assert_response :success
  end

  test "should get pending" do
    get :pending
    assert_response :success
  end

  test "should get failed" do
    get :failed
    assert_response :success
  end
end
