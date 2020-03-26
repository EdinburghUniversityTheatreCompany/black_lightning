require 'test_helper'

class Admin::UsersControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryBot.create(:admin)

    @user = FactoryBot.create(:user)
  end

  test 'should get index' do
    get :index
    assert_response :success
  end

  test 'should get show' do
    get :show, params: { id: @user}
    assert_response :success
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create user' do
    # Remove the existing user:
    User.find(@user.id).destroy

    assert_difference('User.count') do
      post :create, params: { user: { email: @user.email } }
    end

    assert_redirected_to admin_user_path(assigns(:user))
  end

  test 'should get edit' do
    get :edit, params: { id: @user}
    assert_response :success
  end

  test 'should update user' do
    put :update, params: {id: @user, user: { first_name: 'Test' }}
    assert_redirected_to admin_user_path(@user)
  end

  test 'should destroy user' do
    assert_difference('User.count', -1) do
      delete :destroy, params: { id: @user}
    end

    assert_redirected_to admin_users_path
  end
end
