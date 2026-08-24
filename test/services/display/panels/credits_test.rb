require "test_helper"

class Display::Panels::CreditsTest < ActiveSupport::TestCase
  test "is unavailable when nothing is upcoming" do
    Event.delete_all

    assert_not Display::Panels::Credits.new.available?
  end

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

  test "falls back to the next show when nothing runs today" do
    upcoming = FactoryBot.create(:show, is_public: true, team_member_count: 3,
                                        start_date: Date.current + 4, end_date: Date.current + 5)

    assert_equal upcoming.id, Display::Panels::Credits.new.locals[:event].id
  end

  test "splits cast from crew" do
    show = FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 1)
    FactoryBot.create(:team_member, teamwork: show, position: "Actor (Abigail)")
    FactoryBot.create(:team_member, teamwork: show, position: "Lighting Designer")

    locals = Display::Panels::Credits.new.locals

    assert_equal 1, locals[:cast].size
    assert_equal 1, locals[:crew].size
  end
end
