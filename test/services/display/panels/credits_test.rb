require "test_helper"

class Display::Panels::CreditsTest < ActiveSupport::TestCase
  test "is unavailable when the show has no team recorded" do
    FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 1)

    assert_not Display::Panels::Credits.new.available?
  end

  test "prefers the show running today over the next one" do
    later = FactoryBot.create(:show, is_public: true, team_member_count: 2,
                                     start_date: Date.current + 5, end_date: Date.current + 6)
    tonight = FactoryBot.create(:show, is_public: true, team_member_count: 2,
                                       start_date: Date.current, end_date: Date.current + 1)

    panel = Display::Panels::Credits.new

    assert panel.available?
    assert_equal tonight.id, panel.locals[:event].id
    assert_not_equal later.id, panel.locals[:event].id
  end
end
