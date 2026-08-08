require "test_helper"

class Climate::MarginSeriesTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  def range(from:, to:)
    Climate::DateRange.from_params({ from: from, to: to })
  end

  def series_for(sensors, from:, to:)
    Climate::MarginSeries.new(sensors: Array(sensors), range: range(from: from, to: to)).series
  end

  # The whole reason this service exists. MIN(temp) - MAX(dew) takes its two
  # figures from different instants and invents a crypt that never existed.
  test "takes the worst margin in a bucket, not the coldest temperature against the wettest dew point" do
    sensor = create_climate_sensor(in_crypt: true)
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:00"),
                           temperature_c: 12.0, dew_point_c: 9.0) # margin 3.0
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:30"),
                           temperature_c: 10.0, dew_point_c: 5.0) # margin 5.0

    points = series_for(sensor, from: "2026-07-25", to: "2026-08-06").first[:points]

    assert_equal 1, points.size
    # MIN(temp) - MAX(dew) would be 10.0 - 9.0 = 1.0.
    assert_in_delta 3.0, points.first[:margin], 0.001
  end

  test "returns one series per sensor even when a sensor has no readings" do
    with_data = create_climate_sensor(display_name: "North", in_crypt: true)
    without = create_climate_sensor(display_name: "South", in_crypt: true)
    create_climate_reading(sensor: with_data, recorded_at: Time.zone.parse("2026-08-05 12:00"))

    result = series_for([ with_data, without ], from: "2026-08-05", to: "2026-08-06")

    assert_equal 2, result.size
    assert_empty result.last[:points]
  end

  test "carries the sensor's own colour index" do
    sensor = create_climate_sensor(in_crypt: true)
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:00"))

    expected = Climate::SeriesColors.new.index_for(sensor)

    assert_equal expected, series_for(sensor, from: "2026-08-05", to: "2026-08-06").first[:color_index]
  end

  test "breaks the line across a gap rather than drawing through it" do
    # The 11:00 -> 12:00 baseline pair establishes the sensor's own hourly
    # cadence at this bucket width, so the 8-hour jump to 20:00 reads as a
    # real outage rather than this sensor simply reporting every 8 hours —
    # see Climate::Buckets#gap_threshold.
    sensor = create_climate_sensor(in_crypt: true)
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 11:00"))
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:00"))
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 20:00"))

    points = series_for(sensor, from: "2026-07-25", to: "2026-08-06").first[:points]

    assert_equal 4, points.size
    assert_nil points[2][:margin]
  end

  test "skips a reading with no dew point rather than treating it as zero" do
    sensor = create_climate_sensor(in_crypt: true)
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:00"),
                           temperature_c: 12.0, dew_point_c: 9.0)
    Climate::Reading.create!(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:30"),
                             temperature_c: 12.0, relative_humidity: nil, dew_point_c: nil)

    points = series_for(sensor, from: "2026-07-25", to: "2026-08-06").first[:points]

    assert_in_delta 3.0, points.first[:margin], 0.001
  end

  test "returns nothing when no sensor is marked as being in the crypt" do
    assert_empty series_for([], from: "2026-08-05", to: "2026-08-06")
  end
end
