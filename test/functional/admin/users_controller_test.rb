require 'test_helper'

class Admin::UsersControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)

    @user = FactoryBot.create(:user)
  end

  test 'should get index' do
    get :index
    assert_response :success
  end

  test 'should get show' do
    get :show, params: { id: @user }
    assert_response :success
    assert assigns(:link_to_admin_events)
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create user' do
    attributes = FactoryBot.attributes_for(:user)

    assert_difference('User.count') do
      post :create, params: { user: attributes }
    end

    assert_redirected_to admin_user_path(assigns(:user))
  end

  test 'should not create invalid user' do
    attributes = FactoryBot.attributes_for(:user, email: '')

    assert_no_difference('User.count') do
      post :create, params: { user: attributes }
    end

    assert_response :unprocessable_entity
  end

  test 'should get edit' do
    get :edit, params: { id: @user }
    assert_response :success
  end

  test 'should update user' do
    attributes = FactoryBot.attributes_for(:user)

    put :update, params: { id: @user, user: attributes }

    assert_redirected_to admin_user_path(@user)
  end

  test 'should not update invalid user' do
    attributes = FactoryBot.attributes_for(:user, phone_number: 'This is not a phone number! This is a sentence!')

    put :update, params: { id: @user, user: attributes }

    assert_response :unprocessable_entity
  end

  test 'should destroy user' do
    assert_difference('User.count', -1) do
      delete :destroy, params: { id: @user }
    end

    assert_redirected_to admin_users_path
  end

  test 'should reset password' do
    post :reset_password, params: { id: @user }

    assert_redirected_to admin_user_url(@user)
  end

  test 'get autocomplete list' do
    members = FactoryBot.create_list :member, 5
    user = FactoryBot.create :user

    get :autocomplete_list

    members.each { |member| assert_includes_user(member) }

    assert_not_includes response.body, user.first_name
    assert_not_includes response.body, user.last_name
    assert_not_includes response.body, user.id.to_s
  end

  test 'get autocomplete list for all users' do
    members = FactoryBot.create_list :member, 2

    users = FactoryBot.create_list :user, 2

    get :autocomplete_list, params: { all_users: 'true' }

    members.each { |member| assert_includes_user(member) }

    users.each { |user| assert_includes_user(user) }
  end

  private

  def assert_includes_user(user)
    assert_includes response.body, user.first_name
    assert_includes response.body, user.last_name
    assert_includes response.body, user.id.to_s
  end
end
