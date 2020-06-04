require 'test_helper'

class ReportsTest < ActiveSupport::TestCase
  test 'create membership report' do
    FactoryBot.create(:member)
    report = Reports::Membership.new.create
    assert report.validate.empty?
  end

  test 'create roles report' do
    report = Reports::Roles.new.create
    assert report.validate.empty?
  end

  test 'create newsletter subscribe report' do
    NewsletterSubscriber.create(email: 'finbar@viking.arrrr')
    report = Reports::NewsletterSubscribers.new.create
    assert report.validate.empty?
  end

  test 'create staffing report' do
    FactoryBot.create(:show)
    report = Reports::Staffing.new(2019, 2021).create
    assert report.validate.empty?
  end
end
