require 'test_helper'

class Admin::AttachmentsControllerTest < ActionController::TestCase
  test 'should get index' do
    sign_in users(:admin)

    get :index

    assert_response :success
    assert_not_nil assigns(:attachments)

    assert_equal 'Attachments', assigns(:title)
  end
end
