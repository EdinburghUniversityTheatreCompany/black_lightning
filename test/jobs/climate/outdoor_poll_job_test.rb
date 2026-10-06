require "test_helper"

class Climate::OutdoorPollJobTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  # Stands in for Climate::OpenMeteoClient.
  class FakeOutdoorSource
    attr_reader :calls

    def initialize(rows: [])
      @rows = rows
      @calls = []
    end

    def hourly_series(latitude:, longitude:)
      @calls << { latitude: latitude, longitude: longitude }
      raise @rows if @rows.is_a?(Exception)

      @rows
    end
  end

  setup { @original_builder = Climate::OutdoorPollJob.client_builder }
  teardown { Climate::OutdoorPollJob.client_builder = @original_builder }

  def use_source(result = rows)
    fake = FakeOutdoorSource.new(rows: result)
    Climate::OutdoorPollJob.client_builder = ->(_sensor) { fake }
    fake
  end

  # Strictly historical hours, so the future-row guard (tested in
  # reading_ingest_test) does not confuse the row arithmetic.
  def rows(count: 4)
    from = (count + 1).hours.ago.change(min: 0)
    Array.new(count) do |index|
      { recorded_at: from + index.hours, temperature_c: 15.0 + index,
        relative_humidity: 70.0 + index, dew_point_c: 9.0 + index }
    end
  end

  test "creates the outdoor sensor if it is not there yet" do
    Climate::Sensor.where(source: Climate::Sensor::SOURCE_OPEN_METEO).destroy_all
    use_source

    assert_difference -> { Climate::Sensor.where(source: Climate::Sensor::SOURCE_OPEN_METEO).count }, 1 do
      Climate::OutdoorPollJob.perform_now
    end
  end

  test "stores the fetched window" do
    use_source(rows(count: 4))

    Climate::OutdoorPollJob.perform_now

    assert_equal 4, outdoor_climate_sensor.readings.count
  end

  test "asks for the sensor's own coordinates" do
    fake = use_source

    Climate::OutdoorPollJob.perform_now

    assert_in_delta 55.9467, fake.calls.first[:latitude], 0.0001
    assert_in_delta(-3.1903, fake.calls.first[:longitude], 0.0001)
  end

  test "records last_polled_at and clears last_error on success" do
    sensor = outdoor_climate_sensor
    sensor.update_columns(last_error: "yesterday's failure")
    use_source

    Climate::OutdoorPollJob.perform_now
    sensor.reload

    assert_not_nil sensor.last_polled_at
    assert_nil sensor.last_error
  end

  test "a failure while the outdoor line is current is recorded, not reported" do
    # The free tier sheds load with the odd 503, and the next poll re-serves the window.
    sensor = outdoor_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: 1.hour.ago)
    use_source(Climate::OpenMeteoClient::Error.new("503"))

    notices = capture_honeybadger_notices { Climate::OutdoorPollJob.perform_now }

    assert_empty notices
    assert_match(/503/, sensor.reload.last_error)
  end

  test "a failure is reported once the outdoor line has been missing for a day" do
    sensor = outdoor_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: 25.hours.ago)
    use_source(Climate::OpenMeteoClient::Error.new("503"))

    notices = capture_honeybadger_notices { Climate::OutdoorPollJob.perform_now }

    assert_equal 1, notices.size
    assert_in_delta 25.hours.ago.to_i,
                    notices.first.last[:context][:latest_reading_at].to_i, 5
  end

  test "a failure is reported when the sensor has never had a reading" do
    outdoor_climate_sensor
    use_source(Climate::OpenMeteoClient::Error.new("503"))

    notices = capture_honeybadger_notices { Climate::OutdoorPollJob.perform_now }

    assert_equal 1, notices.size
  end

  test "skips an outdoor sensor that has been deactivated" do
    outdoor_climate_sensor.update!(active: false)
    fake = use_source

    Climate::OutdoorPollJob.perform_now

    assert_empty fake.calls
  end

  test "does not touch the govee sensors" do
    govee = create_climate_sensor
    use_source

    Climate::OutdoorPollJob.perform_now

    assert_equal 0, govee.readings.count
  end
end
