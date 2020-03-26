require 'test_helper'

class Admin::DebtsControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryBot.create(:admin)
    @user = FactoryBot.create(:member)
  end

  test "should get index" do
    get :index
    assert_response :success
  end

  test "should get show" do
    get :show, params: { id: @user.id }
    assert_response :success
  end

end
