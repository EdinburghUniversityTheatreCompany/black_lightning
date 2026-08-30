require "test_helper"

##
# Reading a list of performances back as the shape a human would describe it:
# "Wed 11 - Sun 15 October", "Every Friday", or a list when it is neither.
##
class Event::ScheduleTest < ActiveSupport::TestCase
  def show(start_date: Date.new(2026, 10, 11), days: 10)
    FactoryBot.create(:show, start_date: start_date, end_date: start_date + days)
  end

  def perform(event, date, hour: 19, min: 30, **attributes)
    EventOccurrence.create!(event: event, starts_at: date.in_time_zone.change(hour: hour, min: min), **attributes)
  end

  def schedule(event)
    Event::Schedule.for(event.reload)
  end

  test "an event with no performances has no schedule to describe" do
    assert_equal :none, schedule(show).kind
  end

  test "one performance is a single date" do
    event = show
    perform(event, Date.new(2026, 10, 11))

    assert_equal :single, schedule(event).kind
  end

  # The case Mick asked for: five nights in a row is a range, not five rows.
  test "consecutive nights at the same time collapse to one range" do
    event = show
    (0..4).each { |offset| perform(event, Date.new(2026, 10, 11) + offset) }

    result = schedule(event)

    assert_equal :range, result.kind
    assert_equal 1, result.blocks.length
    assert_equal Date.new(2026, 10, 11), result.blocks.first.starts_on
    assert_equal Date.new(2026, 10, 15), result.blocks.first.ends_on
  end

  test "a gap in the middle splits the run into two blocks" do
    event = show
    [ 0, 1, 3, 4 ].each { |offset| perform(event, Date.new(2026, 10, 11) + offset) }

    result = schedule(event)

    assert_equal :irregular, result.kind
    assert_equal [ [ Date.new(2026, 10, 11), Date.new(2026, 10, 12) ],
                   [ Date.new(2026, 10, 14), Date.new(2026, 10, 15) ] ],
                 result.blocks.map { |block| [ block.starts_on, block.ends_on ] }
  end

  # A Saturday matinee is not part of the evening run, however adjacent it is.
  test "a different curtain time starts a new block" do
    event = show
    perform(event, Date.new(2026, 10, 11))
    perform(event, Date.new(2026, 10, 12))
    perform(event, Date.new(2026, 10, 12), hour: 14, min: 30)

    assert_equal 2, schedule(event).blocks.length
  end

  # A Season open 12pm-1am on Tuesday and 12pm-10pm on Wednesday shares a curtain
  # time but not its hours. Folding them advertised Wednesday as closing at 1am,
  # because the view prints the block's hours from its first occurrence.
  test "the same opening time with a different closing time is a different block" do
    event = show
    perform(event, Date.new(2026, 10, 11), hour: 12,
                   ends_at: Date.new(2026, 10, 12).in_time_zone.change(hour: 1))
    perform(event, Date.new(2026, 10, 12), hour: 12,
                   ends_at: Date.new(2026, 10, 12).in_time_zone.change(hour: 22))

    assert_equal 2, schedule(event).blocks.length
  end

  test "matching hours on consecutive days still fold into one block" do
    event = show
    (0..1).each do |offset|
      date = Date.new(2026, 10, 11) + offset
      perform(event, date, hour: 12, ends_at: date.in_time_zone.change(hour: 22))
    end

    assert_equal 1, schedule(event).blocks.length
  end

  # --- the Improverts --------------------------------------------------

  # A year-long weekly fixture. A date range here reads "Sep 1 - Jun 30", the
  # exact string the box office screen exists to avoid.
  test "the same weekday every week is a weekly pattern" do
    event = show(start_date: Date.new(2026, 9, 4), days: 300)
    friday = Date.new(2026, 9, 4)
    6.times { |week| perform(event, friday + (week * 7)) }

    result = schedule(event)

    assert_equal :weekly, result.kind
    assert_equal 5, result.weekday
    assert_equal "Friday", result.weekday_name
  end

  # Reading week, or a cancelled night. Still recognisably "every Friday".
  test "a skipped week does not break the weekly pattern" do
    event = show(start_date: Date.new(2026, 9, 4), days: 300)
    friday = Date.new(2026, 9, 4)
    [ 0, 1, 3, 4, 5 ].each { |week| perform(event, friday + (week * 7)) }

    assert_equal :weekly, schedule(event).kind
  end

  test "two dates a week apart are not yet a pattern" do
    event = show
    perform(event, Date.new(2026, 10, 11))
    perform(event, Date.new(2026, 10, 18))

    assert_not_equal :weekly, schedule(event).kind
  end

  # Three Fridays inside a fortnight is a short run, not a standing fixture.
  test "a pattern has to span more than a fortnight" do
    event = show(days: 20)
    friday = Date.new(2026, 10, 16)
    3.times { |week| perform(event, friday + (week * 7)) }

    assert_not_equal :weekly, schedule(event).kind
  end

  test "the same weekday at different times is not a weekly pattern" do
    event = show(start_date: Date.new(2026, 9, 4), days: 300)
    friday = Date.new(2026, 9, 4)
    4.times { |week| perform(event, friday + (week * 7), hour: 19 + week) }

    assert_not_equal :weekly, schedule(event).kind
  end

  # --- what a range must not hide --------------------------------------

  # Collapsing five nights into one line loses which of them is the relaxed
  # performance, which is the thing people scan the list for.
  test "flagged and noted performances are reported as exceptions" do
    event = show
    (0..4).each { |offset| perform(event, Date.new(2026, 10, 11) + offset) }
    perform(event, Date.new(2026, 10, 16), access_flags: %w[relaxed])
    perform(event, Date.new(2026, 10, 17), note: "Post-show Q&A")

    exceptions = schedule(event).exceptions

    assert_equal 2, exceptions.length
    assert_equal [ Date.new(2026, 10, 16), Date.new(2026, 10, 17) ], exceptions.map(&:on_date)
  end

  test "an ordinary run has no exceptions" do
    event = show
    (0..4).each { |offset| perform(event, Date.new(2026, 10, 11) + offset) }

    assert_empty schedule(event).exceptions
  end

  test "the shared curtain time is reported when every performance agrees" do
    event = show
    (0..4).each { |offset| perform(event, Date.new(2026, 10, 11) + offset) }

    assert_equal "19:30", schedule(event).time_of_day
  end

  test "no shared curtain time when they differ" do
    event = show
    perform(event, Date.new(2026, 10, 11))
    perform(event, Date.new(2026, 10, 12), hour: 14, min: 30)

    assert_nil schedule(event).time_of_day
  end
end
