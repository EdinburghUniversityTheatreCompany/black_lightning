require "test_helper"

class Climate::SeriesQueryTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  def range(from:, to:)
    Climate::DateRange.from_params({ from: from, to: to })
  end

  def series_for(sensors, from:, to:)
    Climate::SeriesQuery.new(sensors: Array(sensors), range: range(from: from, to: to)).series
  end

  # --- resolution ------------------------------------------------------------

  test "keeps raw ten-minute buckets over a short span" do
    query = Climate::SeriesQuery.new(sensors: [], range: range(from: "2026-08-05", to: "2026-08-06"))

    assert_equal 600, query.bucket_seconds
  end

  test "buckets hourly over a fortnight" do
    query = Climate::SeriesQuery.new(sensors: [], range: range(from: "2026-07-25", to: "2026-08-06"))

    assert_equal 3_600, query.bucket_seconds
  end

  test "buckets six-hourly over a quarter" do
    query = Climate::SeriesQuery.new(sensors: [], range: range(from: "2026-06-01", to: "2026-08-06"))

    assert_equal 21_600, query.bucket_seconds
  end

  test "buckets daily over a year" do
    query = Climate::SeriesQuery.new(sensors: [], range: range(from: "2025-08-06", to: "2026-08-06"))

    assert_equal 86_400, query.bucket_seconds
  end

  # --- shape -----------------------------------------------------------------

  test "returns one series per sensor even when a sensor has no readings" do
    with_data = create_climate_sensor(display_name: "North")
    without = create_climate_sensor(display_name: "South")
    create_climate_reading(sensor: with_data, recorded_at: Time.zone.parse("2026-08-05 12:00"))

    result = series_for([ with_data, without ], from: "2026-08-05", to: "2026-08-06")

    assert_equal 2, result.size
    assert_empty result.last[:points]
  end

  test "each point carries all three measurements" do
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:00"),
                           temperature_c: 12.0, relative_humidity: 80.0)

    point = series_for(sensor, from: "2026-08-05", to: "2026-08-06").first[:points].first

    assert point[:t].present?
    assert_in_delta 12.0, point[:temperature], 0.01
    assert_in_delta 80.0, point[:humidity], 0.01
    assert_not_nil point[:dew_point]
  end

  test "marks the outdoor series so the chart can style it apart" do
    result = series_for(outdoor_climate_sensor, from: "2026-08-05", to: "2026-08-06")

    assert result.first[:outdoor]
  end

  # --- bucketing behaviour ---------------------------------------------------

  test "averages the readings inside one hourly bucket" do
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-07-26 12:10"),
                           temperature_c: 10.0, relative_humidity: 70.0)
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-07-26 12:40"),
                           temperature_c: 14.0, relative_humidity: 80.0)

    points = series_for(sensor, from: "2026-07-25", to: "2026-08-06").first[:points]

    assert_equal 1, points.size
    assert_in_delta 12.0, points.first[:temperature], 0.01
  end

  test "hourly buckets land on the hour boundary" do
    # The UNIX_TIMESTAMP trap would shift these by the server's UTC offset.
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-07-26 12:37"))

    bucket = Time.zone.parse(series_for(sensor, from: "2026-07-25", to: "2026-08-06").first[:points].first[:t])

    assert_equal 12, bucket.hour
    assert_equal 0, bucket.min
    assert_equal 0, bucket.sec
  end

  test "downsamples a long range far below the raw row count" do
    sensor = create_climate_sensor
    # 300 ten-minute readings across two days, viewed over a year.
    300.times do |index|
      create_climate_reading(sensor: sensor,
                             recorded_at: Time.zone.parse("2026-08-01 00:00") + (index * 10).minutes)
    end

    points = series_for(sensor, from: "2025-08-06", to: "2026-08-06").first[:points]

    assert_operator points.size, :<, 10
    assert_operator points.size, :>, 0
  end

  test "excludes readings outside the requested range" do
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:00"))
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-07-01 12:00"))

    points = series_for(sensor, from: "2026-08-05", to: "2026-08-06").first[:points]

    assert_equal 1, points.size
  end

  test "includes a reading late on the final day" do
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-06 23:50"))

    assert_equal 1, series_for(sensor, from: "2026-08-05", to: "2026-08-06").first[:points].size
  end

  test "points come out in chronological order" do
    sensor = create_climate_sensor
    [ "12:00", "10:00", "11:00" ].each do |time|
      create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 #{time}"))
    end

    times = series_for(sensor, from: "2026-08-05", to: "2026-08-06").first[:points].map { |p| p[:t] }

    assert_equal times.sort, times
  end

  test "sensors' points do not bleed into each other" do
    first = create_climate_sensor(display_name: "North")
    second = create_climate_sensor(display_name: "South")
    create_climate_reading(sensor: first, recorded_at: Time.zone.parse("2026-08-05 12:00"), temperature_c: 10.0)
    create_climate_reading(sensor: second, recorded_at: Time.zone.parse("2026-08-05 12:00"), temperature_c: 20.0)

    result = series_for([ first, second ], from: "2026-08-05", to: "2026-08-06")

    assert_in_delta 10.0, result.first[:points].first[:temperature], 0.01
    assert_in_delta 20.0, result.last[:points].first[:temperature], 0.01
  end

  # --- gaps ------------------------------------------------------------------

  test "breaks the line with a null point across an outage" do
    # Without this the chart draws a straight line through the missing hours,
    # which reads as a measurement of the room that never happened.
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 10:00"))
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 18:00"))

    points = series_for(sensor, from: "2026-08-05", to: "2026-08-06").first[:points]

    assert_equal 3, points.size
    assert_nil points[1][:temperature]
  end

  test "draws the outdoor line unbroken on the 24-hour view despite its hourly cadence" do
    # The reported bug: Open-Meteo reports hourly, but the 24-hour view
    # buckets at ten minutes (600s). A gap threshold built from the bucket
    # width alone (600 * 3 = 1800s) is narrower than the 3600s gap between
    # any two consecutive hourly readings, so a null was inserted after
    # EVERY outdoor point — with spanGaps: false and pointRadius: 0 that
    # drew nothing at all, even though the legend and end-of-line label
    # still rendered from the (empty-looking) series.
    sensor = outdoor_climate_sensor
    24.times { |hour| create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 00:00") + hour.hours) }

    points = series_for(sensor, from: "2026-08-05", to: "2026-08-06").first[:points]

    assert_equal 24, points.size
    assert(points.none? { |point| point[:temperature].nil? })
  end

  test "still breaks the outdoor line on the 24-hour view across a genuine outage" do
    sensor = outdoor_climate_sensor
    [ 0, 1, 2, 9, 10, 11 ].each do |hour|
      create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 00:00") + hour.hours)
    end

    points = series_for(sensor, from: "2026-08-05", to: "2026-08-06").first[:points]

    assert_includes points.map { |point| point[:temperature] }, nil
  end

  test "does not break the line across an ordinary consecutive gap" do
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 10:00"))
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 10:10"))

    points = series_for(sensor, from: "2026-08-05", to: "2026-08-06").first[:points]

    assert_equal 2, points.size
    assert(points.none? { |p| p[:temperature].nil? })
  end

  test "timestamps serialise as iso8601 strings" do
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:00"))

    t = series_for(sensor, from: "2026-08-05", to: "2026-08-06").first[:points].first[:t]

    assert_kind_of String, t
    assert Time.zone.parse(t).present?
  end

  test "asks the database nothing when there are no sensors" do
    query_count = 0
    callback = ->(*) { query_count += 1 }

    result = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      Climate::SeriesQuery.new(sensors: [], range: range(from: "2026-08-05", to: "2026-08-06")).series
    end

    assert_empty result
    assert_equal 0, query_count
  end

  test "each point carries the spread as well as the mean" do
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:00"),
                           temperature_c: 10.0, relative_humidity: 80.0, dew_point_c: 7.0)
    create_climate_reading(sensor: sensor, recorded_at: Time.zone.parse("2026-08-05 12:30"),
                           temperature_c: 14.0, relative_humidity: 80.0, dew_point_c: 7.0)

    point = series_for(sensor, from: "2026-07-25", to: "2026-08-06").first[:points].first

    assert_in_delta 12.0, point[:temperature], 0.001
    assert_in_delta 10.0, point[:temperature_min], 0.001
    assert_in_delta 14.0, point[:temperature_max], 0.001
  end

  test "reports whether the buckets are wide enough for a spread to mean anything" do
    assert_not_predicate Climate::SeriesQuery.new(sensors: [], range: range(from: "2026-08-05", to: "2026-08-06")), :aggregated?
    assert_predicate Climate::SeriesQuery.new(sensors: [], range: range(from: "2026-07-25", to: "2026-08-06")), :aggregated?
  end
end
