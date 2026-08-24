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

  # sort_by is not stable and every event running today shares the key
  # [0, today], so without the start_date/id tiebreakers the six slot pages --
  # each of which re-sorts independently, minutes apart -- can show the same
  # show twice and skip another. During the Fringe that is the normal state.
  test "events running today keep one total order across repeated calls" do
    Event.delete_all

    later_start = FactoryBot.create(:show, name: "Later start", is_public: true,
                                           start_date: Date.current, end_date: Date.current + 4)
    earlier_start = FactoryBot.create(:show, name: "Earlier start", is_public: true,
                                             start_date: Date.current - 3, end_date: Date.current + 4)
    same_start = FactoryBot.create(:show, name: "Same start", is_public: true,
                                          start_date: Date.current - 3, end_date: Date.current + 2)

    # The key implies: all three are on today, so start_date ascending, then id.
    by_key = [ earlier_start, same_start ].sort_by(&:id).map(&:id) + [ later_start.id ]

    5.times do
      assert_equal by_key, Display::EventPool.upcoming.map(&:id)
    end
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
