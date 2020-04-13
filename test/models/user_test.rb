require 'test_helper'

class Admin::UserTest < ActiveSupport::TestCase
  test 'test notified since returns only users who are in debt and have not received a notification' do
    date = Date.today.advance(days: -7)
    
    # No notification.
    user_one = FactoryBot.create(:user)
    # One notification that is from before the date.
    user_two = FactoryBot.create(:user)
    FactoryBot.create(:initial_debt_notification, sent_on: date.advance(days:-1), user: user_two)
    # One notification that is on the date.
    user_three = FactoryBot.create(:user)
    FactoryBot.create(:initial_debt_notification, sent_on: date, user: user_three)
    # One notification that is after the date.
    user_four = FactoryBot.create(:user)
    FactoryBot.create(:initial_debt_notification, sent_on: date.advance(days:1), user: user_four)

    notified_users = User.notified_since(date).to_a

    assert_not_includes notified_users, user_one, 'The list of notified users includes the user without any notifications'
    assert_not_includes notified_users, user_two, 'The list of notified users includes the user with a notification from before date'
    assert_not_includes notified_users, user_three, 'The list of notified users includes the user with a notification on the date'
    assert_includes notified_users, user_four, 'The list of notified users does not include the user that should be notified'
  end
end
