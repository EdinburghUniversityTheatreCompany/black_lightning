require "test_helper"

class Display::EventPoolTest < ActiveSupport::TestCase
  test "an event on today sorts ahead of one that started earlier but is not" do
    friday = Date.current.next_occurring(:friday)

    # Started long ago, plays Fridays only, so it is not on today unless today
    # happens to be a Friday.
    weekly = FactoryBot.create(:show, name: "Improverts", is_public: true,
                                      start_date: Date.current - 60, end_date: Date.current + 60,
                                      performance_weekdays: friday.wday.to_s)
    running = FactoryBot.create(:show, name: "Tonight", is_public: true,
                                       start_date: Date.current - 1, end_date: Date.current + 1)

    pool = Display::EventPool.upcoming

    assert_equal running.id, pool.first.id
    assert_includes pool.map(&:id), weekly.id
  end

  test "the pool orders by next occurrence, not by start date" do
    soon  = FactoryBot.create(:show, is_public: true, start_date: Date.current + 2, end_date: Date.current + 3)
    later = FactoryBot.create(:show, is_public: true, start_date: Date.current + 9, end_date: Date.current + 10)

    assert_equal [ soon.id, later.id ], Display::EventPool.upcoming.map(&:id)
  end

  test "a season is in the pool like any other event" do
    festival = FactoryBot.create(:season, is_public: true,
                                          start_date: Date.current + 1, end_date: Date.current + 4)

    assert_includes Display::EventPool.upcoming.map(&:id), festival.id
  end

  test "a workshop is in the pool" do
    workshop = FactoryBot.create(:workshop, is_public: true,
                                            start_date: Date.current + 1, end_date: Date.current + 2)

    assert_includes Display::EventPool.upcoming.map(&:id), workshop.id
  end

  test "private and finished events are excluded" do
    private_event = FactoryBot.create(:show, is_public: false, start_date: Date.current, end_date: Date.current + 1)
    finished      = FactoryBot.create(:show, is_public: true, start_date: Date.current - 9, end_date: Date.current - 8)

    ids = Display::EventPool.upcoming.map(&:id)

    assert_not_includes ids, private_event.id
    assert_not_includes ids, finished.id
  end

  test "an event whose remaining run holds no performance day drops out" do
    friday = Date.current.next_occurring(:friday)
    stale = FactoryBot.create(:show, is_public: true,
                                     start_date: friday + 1, end_date: friday + 6,
                                     performance_weekdays: "5")

    assert_not_includes Display::EventPool.upcoming(on: friday + 1).map(&:id), stale.id
  end

  test "slots wrap around when there are fewer events than slots" do
    events = 4.times.map do |i|
      FactoryBot.create(:show, is_public: true,
                               start_date: Date.current + (i * 2) + 1,
                               end_date: Date.current + (i * 2) + 2)
    end

    got = (1..6).map { |slot| Display::EventPool.slot(slot).id }

    assert_equal [ events[0], events[1], events[2], events[3], events[0], events[1] ].map(&:id), got
  end

  test "slot returns nil when the pool is empty" do
    Event.delete_all

    assert_nil Display::EventPool.slot(1)
  end
end
