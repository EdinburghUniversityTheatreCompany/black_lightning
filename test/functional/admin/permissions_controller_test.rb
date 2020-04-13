require 'test_helper'

class Admin::PermissionsControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryBot.create(:admin)
  end

  test 'should get grid' do
    get :grid
    assert_response :success
  end

  test 'should update permissions' do
    post :update_grid
    assert_redirected_to admin_permissions_path
  end
end
