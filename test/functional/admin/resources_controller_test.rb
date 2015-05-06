require 'test_helper'

class Admin::ResourcesControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryGirl.create(:admin)
  end

  test 'should get tech - lighting' do
    get 'tech/lighting'
    assert_response :success
  end
end
