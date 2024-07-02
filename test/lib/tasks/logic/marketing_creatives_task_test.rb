require 'test_helper'

# Tests the marketing creatives rake tasks.
class MarketingCreativesTaskTest < ActiveSupport::TestCase
  test 'Should notify new sign ups' do
    profile = FactoryBot.create(:marketing_creatives_profile, approved: false)
    older_profile = FactoryBot.create(:marketing_creatives_profile, approved: nil, created_at: DateTime.current.advance(hours: -25, minutes: 1))

    assert_difference 'ActionMailer::Base.deliveries.count' do
      Tasks::Logic::MarketingCreatives.notify_of_new_sign_ups
    end

    mail = ActionMailer::Base.deliveries.last
    assert_includes mail.subject, '2'

    assert_includes mail.html_part.body, '2'
    assert_includes mail.html_part.body, profile.name.html_safe
    assert_includes mail.html_part.body, older_profile.name.html_safe
  end

  test 'should not notify sign-ups older than 25 hours' do
    profile = FactoryBot.create(:marketing_creatives_profile, created_at: DateTime.current.advance(hours: -25, minutes: -1))

    assert_no_difference 'ActionMailer::Base.deliveries.count' do
      Tasks::Logic::MarketingCreatives.notify_of_new_sign_ups
    end

    mail_sample = ActionMailer::Base.deliveries.last
  end

  test 'should not notify approved sign-ups' do
    profile = FactoryBot.create(:marketing_creatives_profile, approved: true)

    assert_no_difference 'ActionMailer::Base.deliveries.count' do
      Tasks::Logic::MarketingCreatives.notify_of_new_sign_ups
    end

    mail_sample = ActionMailer::Base.deliveries.last
  end
end
