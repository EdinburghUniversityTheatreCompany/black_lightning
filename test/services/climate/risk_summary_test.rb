require "test_helper"

class Climate::RiskSummaryTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  # Margin 1.0 — under the 3.0 threshold.
  def at_risk_reading(sensor, at)
    create_climate_reading(sensor: sensor, recorded_at: at, temperature_c: 12.0, dew_point_c: 11.0)
  end

  # Margin 6.0 — comfortably clear.
  def safe_reading(sensor, at)
    create_climate_reading(sensor: sensor, recorded_at: at, temperature_c: 12.0, dew_point_c: 6.0)
  end

  def summary_for(sensor, from:, to:)
    range = Climate::DateRange.from_params({ from: from, to: to })
    Climate::RiskSummary.new(sensors: [ sensor ], range: range).summaries.first
  end

  # "41 of 720 hours" reads as 6% of a month when it may be 8% of the six days
  # the hand-synced sensor actually covered.
  test "counts hours that have readings, not hours in the range" do
    sensor = create_climate_sensor(in_crypt: true)
    base = Time.zone.parse("2026-08-05 00:00")
    3.times { |offset| at_risk_reading(sensor, base + offset.hours) }

    summary = summary_for(sensor, from: "2026-08-01", to: "2026-08-07")

    assert_equal 3, summary[:hours_with_readings]
    assert_equal 3, summary[:hours_at_risk]
  end

  test "several readings inside one hour count as one hour" do
    sensor = create_climate_sensor(in_crypt: true)
    base = Time.zone.parse("2026-08-05 00:00")
    [ 0, 10, 20, 30, 40, 50 ].each { |minutes| at_risk_reading(sensor, base + minutes.minutes) }

    assert_equal 1, summary_for(sensor, from: "2026-08-01", to: "2026-08-07")[:hours_with_readings]
  end

  test "an hour counts as at risk when its worst reading dips under the threshold" do
    sensor = create_climate_sensor(in_crypt: true)
    base = Time.zone.parse("2026-08-05 00:00")
    safe_reading(sensor, base)
    at_risk_reading(sensor, base + 30.minutes)

    assert_equal 1, summary_for(sensor, from: "2026-08-01", to: "2026-08-07")[:hours_at_risk]
  end

  test "a margin exactly on the threshold is not at risk" do
    sensor = create_climate_sensor(in_crypt: true)
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 00:00"),
                           temperature_c: 12.0, dew_point_c: 9.0) # margin exactly 3.0

    assert_equal 0, summary_for(sensor, from: "2026-08-01", to: "2026-08-07")[:hours_at_risk]
  end

  # Readings arrive by hand-synced CSV, so multi-day holes are normal. Joining
  # across one would claim an unbroken damp spell that nothing measured.
  test "a gap in coverage breaks the longest spell" do
    sensor = create_climate_sensor(in_crypt: true)
    base = Time.zone.parse("2026-08-05 00:00")
    [ 0, 1, 3, 4, 5 ].each { |offset| at_risk_reading(sensor, base + offset.hours) }

    summary = summary_for(sensor, from: "2026-08-01", to: "2026-08-07")

    assert_equal 5, summary[:hours_at_risk]
    assert_equal 3, summary[:longest_spell_hours]
  end

  test "a safe hour also breaks the spell" do
    sensor = create_climate_sensor(in_crypt: true)
    base = Time.zone.parse("2026-08-05 00:00")
    at_risk_reading(sensor, base)
    at_risk_reading(sensor, base + 1.hour)
    safe_reading(sensor, base + 2.hours)
    at_risk_reading(sensor, base + 3.hours)

    assert_equal 2, summary_for(sensor, from: "2026-08-01", to: "2026-08-07")[:longest_spell_hours]
  end

  test "reports when the longest spell ended" do
    sensor = create_climate_sensor(in_crypt: true)
    base = Time.zone.parse("2026-08-05 00:00")
    at_risk_reading(sensor, base)
    at_risk_reading(sensor, base + 1.hour)

    summary = summary_for(sensor, from: "2026-08-01", to: "2026-08-07")

    assert_equal base + 2.hours, summary[:longest_spell_ended_at]
  end

  test "the per-day figures sum to the headline figure" do
    sensor = create_climate_sensor(in_crypt: true)
    at_risk_reading(sensor, Time.zone.parse("2026-08-04 22:00"))
    at_risk_reading(sensor, Time.zone.parse("2026-08-05 01:00"))
    at_risk_reading(sensor, Time.zone.parse("2026-08-05 02:00"))
    safe_reading(sensor, Time.zone.parse("2026-08-06 02:00"))

    summary = summary_for(sensor, from: "2026-08-01", to: "2026-08-07")

    assert_equal 3, summary[:days].size
    assert_equal summary[:hours_at_risk], summary[:days].sum { |day| day[:at_risk_hours] }
    assert_equal summary[:hours_with_readings], summary[:days].sum { |day| day[:hours_with_readings] }
  end

  test "a sensor with no readings reports zeroes rather than nil" do
    sensor = create_climate_sensor(in_crypt: true)

    summary = summary_for(sensor, from: "2026-08-01", to: "2026-08-07")

    assert_equal 0, summary[:hours_with_readings]
    assert_equal 0, summary[:hours_at_risk]
    assert_equal 0, summary[:longest_spell_hours]
    assert_nil summary[:longest_spell_ended_at]
    assert_empty summary[:days]
  end

  test "carries the sensor's own colour index so the bars match its line" do
    sensor = create_climate_sensor(in_crypt: true)

    expected = Climate::SeriesColors.new.index_for(sensor)

    assert_equal expected, summary_for(sensor, from: "2026-08-01", to: "2026-08-07")[:color_index]
  end

  test "keeps each sensor's figures separate" do
    north = create_climate_sensor(display_name: "North", in_crypt: true)
    south = create_climate_sensor(display_name: "South", in_crypt: true)
    at_risk_reading(north, Time.zone.parse("2026-08-05 00:00"))
    safe_reading(south, Time.zone.parse("2026-08-05 00:00"))

    range = Climate::DateRange.from_params({ from: "2026-08-01", to: "2026-08-07" })
    summaries = Climate::RiskSummary.new(sensors: [ north, south ], range: range).summaries

    assert_equal 1, summaries.first[:hours_at_risk]
    assert_equal 0, summaries.last[:hours_at_risk]
  end
end
