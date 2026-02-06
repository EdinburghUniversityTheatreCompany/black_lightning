require "test_helper"

class ReportsMailerTest < ActionMailer::TestCase
  test "send report" do
    user = FactoryBot.create(:user)

    mail = nil

    assert_difference "ActionMailer::Base.deliveries.count" do
      mail = ReportsMailer.send_report(user, "Reports::Roles").deliver_now
    end

    assert_equal [ user.email ], mail.to
    assert_equal "Bedlam Theatre Report", mail.subject
  end
end
