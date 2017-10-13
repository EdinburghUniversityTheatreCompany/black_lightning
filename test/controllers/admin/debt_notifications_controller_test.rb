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

  test "should not get new" do
    get :new
    assert_redirected_to admin_debt_notifications_url
  end


  test "should show admin_debt_notification" do
    get :show, id: @admin_debt_notification
    assert_response :success
  end

  test "should not get edit" do
    get :edit, id: @admin_debt_notification
    assert_redirected_to admin_debt_notifications_url
  end


end
