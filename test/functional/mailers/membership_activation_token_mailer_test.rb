require "test_helper"

class MembershipActivationTokenMailerTest < ActionMailer::TestCase
  test "should send activation" do
    token = MembershipActivationToken.create

    email = "finbar@viking.arrrrr"

    assert_difference "ActionMailer::Base.deliveries.count" do
      mail = MembershipActivationTokenMailer.send_activation(email, token).deliver_now

      assert_equal [ email ], mail.to
      assert_includes mail.html_part.body, token.token
      assert_includes mail.text_part.body, token.token
    end
  end
end
