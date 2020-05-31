require 'test_helper'

class Admin::RolesControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)

    @role = roles(:member)
  end

  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:roles)
  end

  test 'should get role' do
    get :show, params: { id: @role }
    assert_response :success
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
