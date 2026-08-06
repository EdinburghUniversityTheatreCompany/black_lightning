require "test_helper"

class Climate::ReadingIngestTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  # --- bucketing -------------------------------------------------------------

  test "floors a timestamp to the ten-minute bucket" do
    assert_equal Time.zone.parse("2026-08-06 14:20:00"),
                 Climate::ReadingIngest.bucket(Time.zone.parse("2026-08-06 14:27:31"))
  end

  test "a timestamp already on a bucket boundary is unchanged" do
    on_boundary = Time.zone.parse("2026-08-06 14:20:00")

    assert_equal on_boundary, Climate::ReadingIngest.bucket(on_boundary)
  end

  # --- govee ingest ----------------------------------------------------------

  test "records a celsius sensor's reading unchanged" do
    sensor = create_climate_sensor(temperature_unit: Climate::Sensor::UNIT_CELSIUS)

    Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: 12.4,
                                         relative_humidity: 78, at: Time.zone.parse("2026-08-06 14:23"))
    reading = sensor.readings.sole

    assert_in_delta 12.4, reading.temperature_c.to_f, 0.001
    assert_in_delta 78.0, reading.relative_humidity.to_f, 0.001
    assert_equal Time.zone.parse("2026-08-06 14:20"), reading.recorded_at
  end

  test "converts a fahrenheit sensor's raw value to celsius" do
    # This is the whole point of the unit column: 53.6 F is 12 C, and storing
    # 53.6 as a Celsius crypt temperature would be nonsense that never recovers.
    sensor = create_climate_sensor(temperature_unit: Climate::Sensor::UNIT_FAHRENHEIT)

    Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: 53.6, relative_humidity: 78)

    assert_in_delta 12.0, sensor.readings.sole.temperature_c.to_f, 0.01
  end

  test "stores the raw value and the unit it was written under" do
    # The reversibility guarantee: a wrong temperature_unit becomes a backfill
    # from raw_temperature rather than a permanent hole in the history.
    sensor = create_climate_sensor(temperature_unit: Climate::Sensor::UNIT_FAHRENHEIT)

    Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: 53.6, relative_humidity: 78)
    reading = sensor.readings.sole

    assert_in_delta 53.6, reading.raw_temperature.to_f, 0.001
    assert_equal "F", reading.raw_temperature_unit
  end

  test "computes and stores dew point" do
    sensor = create_climate_sensor

    Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: 20.0, relative_humidity: 50)

    assert_in_delta 9.26, sensor.readings.sole.dew_point_c.to_f, 0.05
  end

  test "refuses to write for a sensor whose unit has not been verified" do
    # The primary defence. Writing nothing is recoverable; writing Fahrenheit as
    # Celsius is not.
    sensor = create_climate_sensor(temperature_unit: nil)

    assert_raises(Climate::ReadingIngest::UnverifiedUnitError) do
      Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: 53.6, relative_humidity: 78)
    end
    assert_equal 0, sensor.readings.count
  end

  test "a second poll inside the same bucket updates rather than duplicating" do
    sensor = create_climate_sensor
    at = Time.zone.parse("2026-08-06 14:23")

    Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: 12.0,
                                         relative_humidity: 78, at: at)
    Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: 12.5,
                                         relative_humidity: 79, at: at + 4.minutes)

    assert_equal 1, sensor.readings.count
    assert_in_delta 12.5, sensor.readings.sole.temperature_c.to_f, 0.001
  end

  test "readings in different buckets are separate rows" do
    sensor = create_climate_sensor
    at = Time.zone.parse("2026-08-06 14:23")

    Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: 12.0,
                                         relative_humidity: 78, at: at)
    Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: 12.5,
                                         relative_humidity: 79, at: at + 11.minutes)

    assert_equal 2, sensor.readings.count
  end

  test "two sensors in the same bucket do not collide" do
    first = create_climate_sensor(display_name: "North")
    second = create_climate_sensor(display_name: "South")
    at = Time.zone.parse("2026-08-06 14:23")

    Climate::ReadingIngest.record_govee!(sensor: first, raw_temperature: 12.0,
                                         relative_humidity: 78, at: at)
    Climate::ReadingIngest.record_govee!(sensor: second, raw_temperature: 13.0,
                                         relative_humidity: 80, at: at)

    assert_equal 1, first.readings.count
    assert_equal 1, second.readings.count
  end

  # --- plausibility guard ----------------------------------------------------

  test "rejects a temperature above the plausible range" do
    # The second net under the unit rule: a 20 C crypt read as Fahrenheit lands
    # at 68 C, which is not a temperature any Edinburgh basement reaches.
    sensor = create_climate_sensor

    assert_raises(Climate::ReadingIngest::ImplausibleReading) do
      Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: 68.0, relative_humidity: 78)
    end
    assert_equal 0, sensor.readings.count
  end

  test "rejects a temperature below the plausible range" do
    sensor = create_climate_sensor

    assert_raises(Climate::ReadingIngest::ImplausibleReading) do
      Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: -40.0, relative_humidity: 78)
    end
  end

  test "rejects a relative humidity above 100" do
    sensor = create_climate_sensor

    assert_raises(Climate::ReadingIngest::ImplausibleReading) do
      Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: 12.0, relative_humidity: 140)
    end
  end

  test "rejects a reading with no temperature at all" do
    sensor = create_climate_sensor

    assert_raises(Climate::ReadingIngest::ImplausibleReading) do
      Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: nil, relative_humidity: 78)
    end
  end

  test "accepts the extremes of the plausible range" do
    sensor = create_climate_sensor

    Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: 50.0, relative_humidity: 100,
                                         at: Time.zone.parse("2026-08-06 14:00"))
    Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: -20.0, relative_humidity: 0.5,
                                         at: Time.zone.parse("2026-08-06 15:00"))

    assert_equal 2, sensor.readings.count
  end

  test "a fahrenheit sensor is judged on the converted value, not the raw one" do
    # 120 F is 48.9 C — inside the range. Guarding the raw number would reject a
    # perfectly good reading.
    sensor = create_climate_sensor(temperature_unit: Climate::Sensor::UNIT_FAHRENHEIT)

    Climate::ReadingIngest.record_govee!(sensor: sensor, raw_temperature: 120.0, relative_humidity: 40)

    assert_in_delta 48.89, sensor.readings.sole.temperature_c.to_f, 0.01
  end

  # --- outdoor window upsert -------------------------------------------------

  def outdoor_rows(count: 3, from: Time.zone.parse("2026-08-06 10:00"), temperature: 17.0)
    Array.new(count) do |index|
      { recorded_at: from + index.hours, temperature_c: temperature + index,
        relative_humidity: 70.0 + index, dew_point_c: 11.0 + index }
    end
  end

  test "upserts a whole window of outdoor rows" do
    sensor = outdoor_climate_sensor

    Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: outdoor_rows)

    assert_equal 3, sensor.readings.count
    assert_in_delta 17.0, sensor.readings.chronological.first.temperature_c.to_f, 0.001
  end

  test "re-upserting an overlapping window leaves the row count unchanged" do
    # This IS the self-healing property: the hourly poll re-sends the last two
    # days every time, and must not multiply rows.
    sensor = outdoor_climate_sensor
    Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: outdoor_rows)

    assert_no_difference -> { Climate::Reading.count } do
      Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: outdoor_rows)
    end
  end

  test "re-upserting refreshes a corrected value" do
    # Open-Meteo revises recent hours as observations land, so the second pass
    # must overwrite rather than be dropped.
    sensor = outdoor_climate_sensor
    Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: outdoor_rows(count: 1))
    Climate::ReadingIngest.upsert_series!(sensor: sensor,
                                          rows: outdoor_rows(count: 1, temperature: 19.5))

    assert_in_delta 19.5, sensor.readings.sole.temperature_c.to_f, 0.001
  end

  test "a re-run after a gap backfills the missing hours" do
    sensor = outdoor_climate_sensor
    Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: outdoor_rows(count: 5))
    # Simulate an outage having lost the middle of the window.
    sensor.readings.chronological.to_a[1..2].each(&:destroy)

    assert_equal 3, sensor.readings.count

    Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: outdoor_rows(count: 5))

    assert_equal 5, sensor.readings.count
  end

  test "upserting an empty window is a no-op rather than an error" do
    sensor = outdoor_climate_sensor

    assert_nothing_raised { Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: []) }
  end

  test "drops rows dated in the future" do
    # forecast_days=1 is requested only for self-heal margin; storing the
    # forecast tail would draw predictions as though they were observations.
    sensor = outdoor_climate_sensor
    rows = [ { recorded_at: 1.hour.ago, temperature_c: 15.0, relative_humidity: 70.0, dew_point_c: 9.0 },
             { recorded_at: 3.hours.from_now, temperature_c: 16.0, relative_humidity: 72.0, dew_point_c: 10.0 } ]

    Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: rows)

    assert_equal 1, sensor.readings.count
  end

  test "skips an implausible outdoor row without losing the rest of the window" do
    # One bad row from a weather API must not cost us the other 71.
    sensor = outdoor_climate_sensor
    rows = outdoor_rows(count: 3)
    rows[1] = rows[1].merge(temperature_c: 900.0)

    Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: rows)

    assert_equal 2, sensor.readings.count
  end
end
