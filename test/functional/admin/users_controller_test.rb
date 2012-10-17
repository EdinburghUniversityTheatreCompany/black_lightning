require 'test_helper'

class Admin::UsersControllerTest < ActionController::TestCase
  setup do
    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
    
    @user = users(:one)
  end
  
  test "should get index" do
    get :index
    assert_response :success
  end

  test "should get show" do
    get :show, id: @user
    assert_response :success
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @user
    assert_response :success
  end

end
