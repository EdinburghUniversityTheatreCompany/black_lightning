require 'test_helper'

class Admin::DebtNotificationsControllerTest < ActionController::TestCase
  setup do
    @admin_debt_notification = FactoryGirl.create(:initial_debt_notification)
    sign_in FactoryGirl.create(:admin)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:debt_notifications)
  end

end
