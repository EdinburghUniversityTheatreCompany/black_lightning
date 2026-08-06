require "test_helper"

class Climate::DateRangeTest < ActiveSupport::TestCase
  test "defaults to the last seven days including today" do
    range = Climate::DateRange.from_params({})

    assert_equal Date.current, range.to
    assert_equal Date.current - 6.days, range.from
    assert_equal 7, range.days
  end

  test "honours explicit from and to" do
    range = Climate::DateRange.from_params({ from: "2026-08-01", to: "2026-08-06" })

    assert_equal Date.new(2026, 8, 1), range.from
    assert_equal Date.new(2026, 8, 6), range.to
  end

  test "covers the whole of the end day" do
    # "to 6 August" means up to the end of the 6th; ending at its midnight would
    # silently drop a day of readings off every range.
    range = Climate::DateRange.from_params({ from: "2026-08-01", to: "2026-08-06" })

    assert_equal Time.zone.parse("2026-08-01 00:00:00"), range.starts_at
    assert_equal Date.new(2026, 8, 6), range.ends_at.to_date
    assert_equal 23, range.ends_at.hour
  end

  test "swaps a reversed range and says so" do
    range = Climate::DateRange.from_params({ from: "2026-08-06", to: "2026-08-01" })

    assert_equal Date.new(2026, 8, 1), range.from
    assert_equal Date.new(2026, 8, 6), range.to
    assert_match(/wrong way round/i, range.notice)
  end

  test "trims a range longer than a year and says so" do
    range = Climate::DateRange.from_params({ from: "2020-01-01", to: "2026-08-06" })

    assert_equal Climate::DateRange::MAX_DAYS, range.days
    assert_equal Date.new(2026, 8, 6), range.to
    assert_match(/trimmed/i, range.notice)
  end

  test "falls back to the default and says so when a date cannot be read" do
    # Never silently render a different range as though it were the one asked
    # for. That is how someone reads last week's damp as this week's.
    range = Climate::DateRange.from_params({ from: "not-a-date", to: "" })

    assert_equal 7, range.days
    assert_match(/could not be read/i, range.notice)
  end

  test "a valid range carries no notice" do
    assert_nil Climate::DateRange.from_params({ from: "2026-08-01", to: "2026-08-06" }).notice
  end

  test "to_param round-trips as readable iso dates" do
    range = Climate::DateRange.from_params({ from: "2026-08-01", to: "2026-08-06" })

    assert_equal({ from: "2026-08-01", to: "2026-08-06" }, range.to_param)
  end

  test "a single day is a valid one-day range" do
    range = Climate::DateRange.from_params({ from: "2026-08-06", to: "2026-08-06" })

    assert_equal 1, range.days
    assert_nil range.notice
  end

  test "an explicit to with no from still gets the default width" do
    range = Climate::DateRange.from_params({ to: "2026-08-06" })

    assert_equal Date.new(2026, 7, 31), range.from
    assert_equal Date.new(2026, 8, 6), range.to
  end
end
