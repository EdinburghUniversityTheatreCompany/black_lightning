require 'test_helper'

class Admin::JobControlControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryGirl.create(:admin)
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
