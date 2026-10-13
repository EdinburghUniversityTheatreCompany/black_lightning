require "test_helper"

class Climate::ReadingIngestTest < ActiveSupport::TestCase
  include ClimateTestHelpers

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
    assert_in_delta 17.0, sensor.readings.order(:recorded_at).first.temperature_c.to_f, 0.001
  end

  test "computes the dew point when a row has none" do
    sensor = outdoor_climate_sensor

    Climate::ReadingIngest.upsert_series!(sensor: sensor,
                                          rows: outdoor_rows(count: 1).map { |row| row.except(:dew_point_c) })

    assert_in_delta Climate::DewPoint.celsius(temperature_c: 17.0, relative_humidity: 70.0),
                    sensor.readings.sole.dew_point_c.to_f, 0.01
  end

  test "re-upserting refreshes a corrected value" do
    # The hourly poll re-sends the last two days and Open-Meteo revises recent
    # hours, so the second pass must overwrite rather than add a row.
    sensor = outdoor_climate_sensor
    Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: outdoor_rows(count: 1))
    Climate::ReadingIngest.upsert_series!(sensor: sensor,
                                          rows: outdoor_rows(count: 1, temperature: 19.5))

    assert_in_delta 19.5, sensor.readings.sole.temperature_c.to_f, 0.001
  end

  test "a re-run after a gap backfills the missing hours" do
    # Why Open-Meteo was chosen: past_days re-serves recent history, so the next
    # poll repairs whatever an outage lost.
    sensor = outdoor_climate_sensor
    Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: outdoor_rows(count: 5))
    sensor.readings.order(:recorded_at).to_a[1..2].each(&:destroy)

    assert_equal 3, sensor.readings.count

    Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: outdoor_rows(count: 5))

    assert_equal 5, sensor.readings.count
  end

  test "upserting an empty window is a no-op rather than an error" do
    sensor = outdoor_climate_sensor

    assert_nothing_raised { Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: []) }
  end

  test "drops rows dated in the future" do
    # Storing the forecast tail would draw predictions as observations.
    sensor = outdoor_climate_sensor
    rows = [ { recorded_at: 1.hour.ago, temperature_c: 15.0, relative_humidity: 70.0, dew_point_c: 9.0 },
             { recorded_at: 3.hours.from_now, temperature_c: 16.0, relative_humidity: 72.0, dew_point_c: 10.0 } ]

    Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: rows)

    assert_equal 1, sensor.readings.count
  end

  test "skips an implausible outdoor row without losing the rest of the window" do
    sensor = outdoor_climate_sensor
    rows = outdoor_rows(count: 3)
    rows[1] = rows[1].merge(temperature_c: 900.0)

    Climate::ReadingIngest.upsert_series!(sensor: sensor, rows: rows)

    assert_equal 2, sensor.readings.count
  end
end
