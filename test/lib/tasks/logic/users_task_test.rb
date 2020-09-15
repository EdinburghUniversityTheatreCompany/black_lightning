require 'test_helper'

# Tests the user rake tasks.
class UserTaskTest < ActiveSupport::TestCase
  test 'should do nothing when the user has consented recently enough' do
    user = FactoryBot.create(:user, consented: Date.today.advance(years: -1, days: 1))

    phone_number = user.phone_number

    assert_equal 0, Tasks::Logic::Users.clean_up_personal_info

    assert_equal phone_number, user.reload.phone_number
  end

  test 'should clean up phone numbers when the user has consented long ago' do
    user = FactoryBot.create(:user, consented: Date.today.advance(years: -1, days: -1))
    
    assert_equal 1, Tasks::Logic::Users.clean_up_personal_info

    assert_nil user.reload.phone_number
  end
end
