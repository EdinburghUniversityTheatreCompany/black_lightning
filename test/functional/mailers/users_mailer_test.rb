require "test_helper"

class UsersMailerTest < ActionMailer::TestCase
  test "should send welcome_email" do
    user = users(:user)
    mail = nil
    assert_difference "ActionMailer::Base.deliveries.count" do
      mail = UsersMailer.welcome_email(user).deliver_now
    end

    # Test the body of the sent email contains what we expect it to
    assert_equal [ user.email ], mail.to
    assert_equal "Welcome to Bedlam Theatre", mail.subject

    assert_includes mail.html_part.to_s, "This is the test welcome email content"

    assert_includes mail.text_part.to_s, "This is the test welcome email content"
  end
end
