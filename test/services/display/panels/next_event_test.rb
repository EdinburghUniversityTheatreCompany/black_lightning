require "test_helper"

class Display::Panels::NextEventTest < ActiveSupport::TestCase
  test "is unavailable when the pool is empty" do
    Event.delete_all

    assert_not Display::Panels::NextEvent.new(1).available?
  end

  test "slot 1 is the show running today" do
    FactoryBot.create(:show, is_public: true, start_date: Date.current + 5, end_date: Date.current + 6)
    tonight = FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 1)

    panel = Display::Panels::NextEvent.new(1)

    assert panel.available?
    assert_equal tonight.id, panel.locals[:event].id
    assert panel.locals[:tonight], "an event running today should render in tonight mode"
  end

  test "a slot beyond the pool wraps back to the start" do
    first  = FactoryBot.create(:show, is_public: true, start_date: Date.current + 1, end_date: Date.current + 2)
    second = FactoryBot.create(:show, is_public: true, start_date: Date.current + 3, end_date: Date.current + 4)

    assert_equal first.id,  Display::Panels::NextEvent.new(3).locals[:event].id
    assert_equal second.id, Display::Panels::NextEvent.new(4).locals[:event].id
  end

  test "an upcoming event that is not on today is not in tonight mode" do
    FactoryBot.create(:show, is_public: true, start_date: Date.current + 3, end_date: Date.current + 4)

    assert_not Display::Panels::NextEvent.new(1).locals[:tonight]
  end
end
