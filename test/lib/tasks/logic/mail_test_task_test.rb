require 'test_helper'
require 'rake'

# Tests the debt rake tasks.
class MailTestTaskTest < ActiveSupport::TestCase
  test 'Should send test email' do
    assert_difference 'ActionMailer::Base.deliveries.count', 1 do
      Tasks::Logic::Mail.send_test_email('tes@test.test')
    end

    mail_sample = ActionMailer::Base.deliveries.last
    assert_equal 'Check In', mail_sample.subject
  end
end
