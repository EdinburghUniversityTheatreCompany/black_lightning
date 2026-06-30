require "test_helper"

class ReportsTest < ActiveSupport::TestCase
  test "create membership report" do
    FactoryBot.create(:member)
    report = Reports::Membership.new.create
    assert_empty report.validate
  end

  test "create roles report" do
    report = Reports::Roles.new.create
    assert_empty report.validate
  end

  test "create newsletter subscribe report" do
    NewsletterSubscriber.create(email: "finbar@viking.arrrr")
    report = Reports::NewsletterSubscribers.new.create
    assert_empty report.validate
  end

  test "create staffing report" do
    FactoryBot.create(:show)
    report = Reports::Staffing.new(2019, 2021).create
    assert_empty report.validate
  end
end
