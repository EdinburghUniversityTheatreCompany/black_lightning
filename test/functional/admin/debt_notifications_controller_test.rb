require 'test_helper'

class Admin::DebtNotificationsControllerTest < ActionController::TestCase
  setup do
    @admin_debt_notification = FactoryBot.create(:initial_debt_notification)
    sign_in users(:admin)
  end

  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:debt_notifications), 'The debt notifications were not set by the index method'
  end

  test 'should get index with search' do
    name = 'veryspecificquerythatwillnotbearandomname'

    user = FactoryBot.create(:member)
    debt_notification = FactoryBot.create(:initial_debt_notification, user: user)

    other_user = FactoryBot.create(:member, first_name: name)
    other_debt_notification = FactoryBot.create(:initial_debt_notification, user: other_user)

    get :index, params: { first_name: name }

    assert_response :success

    assert_includes assigns(:debt_notifications).to_a, other_debt_notification, 'The debt notifications do not include the expected debt notification'
    assert_includes assigns(:debt_notifications).to_a, debt_notification, 'The debt notifications include an unexpected debt notification'
  end
end
