require 'test_helper'

class UsersMailerTest < ActionMailer::TestCase
  test 'should send welcome_email' do
    user = FactoryBot.create(:member)

    email = UsersMailer.welcome_email(user, true).deliver_now
    assert !ActionMailer::Base.deliveries.empty?

    # Test the body of the sent email contains what we expect it to
    assert_equal [user.email], email.to
    assert_equal 'Welcome to Bedlam Theatre', email.subject
  end
end
