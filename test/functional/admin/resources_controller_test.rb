require 'test_helper'

class Admin::ResourcesControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryGirl.create(:admin)
  end

  test 'should get tech resources' do
    get 'admin/resources/tech'
    assert_response :success
  end
end
