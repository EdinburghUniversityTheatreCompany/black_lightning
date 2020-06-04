require 'test_helper'

class ReportsMailerTest < ActionMailer::TestCase
  test 'send report' do
    report = Reports::Roles.new
    user = FactoryBot.create(:user)

    mail = nil

    assert_difference 'ActionMailer::Base.deliveries.count' do
      mail = ReportsMailer.send_report(user, report).deliver_now
    end

    assert_equal [user.email], mail.to
    assert_equal 'Bedlam Theatre Report', mail.subject
  end
end
