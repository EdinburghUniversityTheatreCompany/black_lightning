require "test_helper"

class UserCalendarTokenTest < ActiveSupport::TestCase
  test "generates calendar_token on create" do
    user = FactoryBot.create(:user)
    assert user.calendar_token.present?
  end

  test "regenerate_calendar_token changes the token" do
    user = FactoryBot.create(:user)
    old_token = user.calendar_token
    user.regenerate_calendar_token
    assert_not_equal old_token, user.reload.calendar_token
  end
end
