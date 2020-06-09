require 'test_helper'

class Admin::RolesControllerTest < ActionController::TestCase
  setup do
    @admin = users(:admin)
    sign_in @admin

    @role = roles(:member)
  end

  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:roles)
  end

  test 'should get members role as admin' do
    members = []
    (0..2).each do 
      members << FactoryBot.create(:member)
    end

    user = FactoryBot.create(:user)
    get :show, params: { id: @role }
    assert_response :success

    members.each do |member|
      assert_match member.name_or_email, response.body
    end

    assert_no_match user.name_or_email, response.body

    assert_match 'Please add members from the membership activation page', response.body
  end

  test 'should get members role as committee' do
    sign_out @admin
    sign_in FactoryBot.create(:committee)
    
    get :show, params: { id: @role }
    assert_response :success

    assert_match 'You are not allowed to add members', response.body
  end

  test 'should get committee role' do
    @role = Role.find_by(name: 'committee')

    get :show, params: { id: @role }
    assert_response :success

    assert_match 'Add User To Role', response.body
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create role' do
    assert_difference('Role.count') do
      post :create, params: { role: { name: 'Hexagon' } }
    end

    assert Role.where(name: 'Hexagon').one?

    assert_redirected_to admin_role_path(assigns(:role))
  end

  test 'should not create invalid role' do
    assert_no_difference('Role.count') do
      post :create, params: { role: { name: nil } }
    end

    assert_response :unprocessable_entity
  end

  test 'should get edit' do
    get :edit, params: { id: @role }
    assert_response :success
  end

  test 'should update role' do
    put :update, params: { id: @role, role: { name: 'Viking' } }

    assert 'Viking', assigns(:role).name
    assert_redirected_to admin_role_path(@role)
  end
  
  test 'should not update invalid role' do
    put :update, params: { id: @role, role: { name: nil } }

    assert_response :unprocessable_entity
  end

  test 'should destroy role' do
    assert_difference('Role.count', -1) do
      delete :destroy, params: { id: @role }
    end

    assert_redirected_to admin_roles_path
  end
end
