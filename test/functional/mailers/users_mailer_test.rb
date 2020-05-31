require 'test_helper'

class UsersMailerTest < ActionMailer::TestCase
  test 'should send welcome_email' do
    user = FactoryBot.create(:member)

    email = nil
    assert_difference 'ActionMailer::Base.deliveries.count' do
      email = UsersMailer.welcome_email(user, true).deliver_now
    end

    # Test the body of the sent email contains what we expect it to
    assert_equal [user.email], email.to
    assert_equal 'Welcome to Bedlam Theatre', email.subject
  end
end
