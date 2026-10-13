require "test_helper"

class Display::EventPoolTest < ActiveSupport::TestCase
  test "an event on today sorts ahead of one that started earlier but is not" do
    friday = Date.current.next_occurring(:friday)

    # Started long ago, next performance is a week off, so it is not on today.
    weekly = FactoryBot.create(:show, name: "Improverts", is_public: true,
                                      start_date: Date.current - 60, end_date: Date.current + 60)
    FactoryBot.create(:event_occurrence, event: weekly, starts_at: (friday + 7).noon + 7.hours)
    running = FactoryBot.create(:show, name: "Tonight", is_public: true,
                                       start_date: Date.current - 1, end_date: Date.current + 1)

    pool = Display::EventPool.upcoming

    assert_equal running.id, pool.first.id
    assert_includes pool.map(&:id), weekly.id
  end

  # sort_by is not stable and every event running today shares [0, today], so
  # without the start_date/id tiebreakers the six slot pages could show one show
  # twice and skip another.
  test "events running today keep one total order across repeated calls" do
    Event.delete_all

    later_start = FactoryBot.create(:show, name: "Later start", is_public: true,
                                           start_date: Date.current, end_date: Date.current + 4)
    earlier_start = FactoryBot.create(:show, name: "Earlier start", is_public: true,
                                             start_date: Date.current - 3, end_date: Date.current + 4)
    same_start = FactoryBot.create(:show, name: "Same start", is_public: true,
                                          start_date: Date.current - 3, end_date: Date.current + 2)

    # All three are on today: start_date ascending, then id.
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

  test "seasons and workshops are in the pool like any other event" do
    %i[season workshop].each do |type|
      event = FactoryBot.create(type, is_public: true, start_date: Date.current + 1, end_date: Date.current + 2)

      assert_includes Display::EventPool.upcoming.map(&:id), event.id, type.to_s
    end
  end

  test "private and finished events are excluded" do
    private_event = FactoryBot.create(:show, is_public: false, start_date: Date.current, end_date: Date.current + 1)
    finished      = FactoryBot.create(:show, is_public: true, start_date: Date.current - 9, end_date: Date.current - 8)

    ids = Display::EventPool.upcoming.map(&:id)

    assert_not_includes ids, private_event.id
    assert_not_includes ids, finished.id
  end

  # The run dates decide what is on: a producer who forgets the second week's
  # performances must not see the show vanish.
  test "an event whose listed performances have all passed stays until its run ends" do
    friday = Date.current.next_occurring(:friday)
    partial = FactoryBot.create(:show, is_public: true,
                                       start_date: friday + 1, end_date: friday + 6)
    FactoryBot.create(:event_occurrence, event: partial, starts_at: (friday + 2).noon + 7.hours)

    assert_includes Display::EventPool.upcoming(on: friday + 4).map(&:id), partial.id
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
