require 'test_helper'

class AboutControllerTest < ActionController::TestCase
  include SubpageHelper

  # Test if getting an existing page works.
  test 'should get a page' do
    assert_routing 'about/acting', controller: 'about', action: 'page', page: 'acting'

    FactoryBot.create(:editable_block, name: 'Acting', url: 'about/acting')

    # To test if it gets the correct subpages.
    FactoryBot.create(:editable_block, name: 'Auditions', url: 'about/acting/auditions')

    get :page, params: { page: 'acting' }
  
    assert_response :success

    assert_equal 'Acting', assigns(:editable_block).name

    assert_equal get_subpages('about/acting'), assigns(:subpages)
  end

  # Test if getting a non-existent page gives a 404.
  test 'should not get non-existent page' do
    get :page, params: { page: 'this/page/does/not/exist/I/think' }
    
    assert_response 404
  end
end
