require 'test_helper'

class Admin::DebtNotificationsControllerTest < ActionController::TestCase
  setup do
    @admin_debt_notification = admin_debt_notifications(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:admin_debt_notifications)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create admin_debt_notification" do
    assert_difference('Admin::DebtNotification.count') do
      post :create, admin_debt_notification: { sent_on: @admin_debt_notification.sent_on, user_id: @admin_debt_notification.user_id }
    end

    assert_redirected_to admin_debt_notification_path(assigns(:admin_debt_notification))
  end

  test "should show admin_debt_notification" do
    get :show, id: @admin_debt_notification
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @admin_debt_notification
    assert_response :success
  end

  test "should update admin_debt_notification" do
    patch :update, id: @admin_debt_notification, admin_debt_notification: { sent_on: @admin_debt_notification.sent_on, user_id: @admin_debt_notification.user_id }
    assert_redirected_to admin_debt_notification_path(assigns(:admin_debt_notification))
  end

  test "should destroy admin_debt_notification" do
    assert_difference('Admin::DebtNotification.count', -1) do
      delete :destroy, id: @admin_debt_notification
    end

    assert_redirected_to admin_debt_notifications_path
  end
end
