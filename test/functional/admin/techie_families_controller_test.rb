require 'test_helper'

class Admin::TechieFamiliesControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryBot.create(:admin)
  end

  test 'should get index' do
    get :index
    assert_response :success
  end
end
