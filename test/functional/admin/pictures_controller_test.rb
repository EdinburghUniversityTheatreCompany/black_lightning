require 'test_helper'

class Admin::PicturesControllerTest < ActionController::TestCase
  test 'should get index' do
    sign_in users(:admin)

    get :index

    assert_response :success
    assert_not_nil assigns(:pictures)

    assert_equal 'Pictures', assigns(:title)
  end
end
