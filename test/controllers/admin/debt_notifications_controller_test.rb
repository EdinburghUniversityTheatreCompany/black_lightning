require 'test_helper'

class Admin::DebtNotificationsControllerTest < ActionController::TestCase
  setup do
    @admin_debt_notification = FactoryBot.create(:initial_debt_notification)
    sign_in FactoryBot.create(:admin)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:debt_notifications)
  end

end
