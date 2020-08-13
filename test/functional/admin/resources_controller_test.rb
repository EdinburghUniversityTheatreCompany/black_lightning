require 'test_helper'

class Admin::ResourcesControllerTest < ActionController::TestCase
  include SubpageHelper

  setup do
    sign_in users(:admin)
  end

  test 'should get tech resources' do
    assert_routing 'admin/resources/tech', controller: 'admin/resources', action: 'page', page: 'tech'

    FactoryBot.create(:editable_block, name: 'Tech', url: 'admin/resources/tech')
    
    # To test if it gets the correct subpages.
    FactoryBot.create(:editable_block, name: 'Lights', url: 'admin/resources/tech/lights')

    get :page, params: { page: 'tech' }
  
    assert_response :success

    assert_equal 'Tech', assigns(:editable_block).name

    assert_equal get_subpages('admin/resources/tech'), assigns(:subpages)
  end

  # Test if getting a non-existent page gives a 404.
  test 'should not get non-existent page' do
    get :page, params: { page: 'this/page/does/not/exist/I/think' }
  
    assert_response 404
  end
end
