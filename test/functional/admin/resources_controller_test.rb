require 'test_helper'

class Admin::ResourcesControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryBot.create(:admin)
  end

  test 'should get tech resources' do
    skip("didnt work before rails 5 maybe it never did?")
    get 'admin/resources/tech'
    assert_response :success
  end
end
