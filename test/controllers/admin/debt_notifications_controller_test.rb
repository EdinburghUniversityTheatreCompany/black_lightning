require 'test_helper'

class Admin::DebtNotificationsControllerTest < ActionController::TestCase
  setup do
    @admin_debt_notification = FactoryBot.create(:initial_debt_notification)
    sign_in FactoryBot.create(:admin)
  end

  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:debt_notifications)
  end

  test 'should get index with search' do
    name = 'veryspecificquerythatwillnotbearandomname'

    other_user = FactoryBot.create(:member, first_name: name)
    other_debt_notification = FactoryBot.create(:initial_debt_notification, user: other_user)

    get :index, params: { user_fname: name }

    assert_response :success

    assert_equal [other_debt_notification], assigns(:debt_notifications).to_a
  end
end
