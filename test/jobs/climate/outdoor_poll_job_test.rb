require "test_helper"

class Climate::OutdoorPollJobTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  setup { @original_builder = Climate::OutdoorPollJob.client_builder }
  teardown { Climate::OutdoorPollJob.client_builder = @original_builder }

  def use_source(fake)
    Climate::OutdoorPollJob.client_builder = ->(_sensor) { fake }
    fake
  end

  # Strictly historical hours. A window running up to "now" would have its last
  # row dropped by the future-row guard, which is correct behaviour but makes
  # the row arithmetic in these tests confusing. That guard has its own test in
  # reading_ingest_test.rb.
  def rows(count: 4)
    from = (count + 1).hours.ago.change(min: 0)
    Array.new(count) do |index|
      { recorded_at: from + index.hours, temperature_c: 15.0 + index,
        relative_humidity: 70.0 + index, dew_point_c: 9.0 + index }
    end
  end

  test "creates the outdoor sensor if it is not there yet" do
    Climate::Sensor.open_meteo.destroy_all
    use_source(ClimateTestHelpers::FakeOutdoorSource.new(rows: rows))

    assert_difference -> { Climate::Sensor.open_meteo.count }, 1 do
      Climate::OutdoorPollJob.perform_now
    end
  end

  test "stores the fetched window" do
    use_source(ClimateTestHelpers::FakeOutdoorSource.new(rows: rows(count: 4)))

    Climate::OutdoorPollJob.perform_now

    assert_equal 4, outdoor_climate_sensor.readings.count
  end

  test "asks for the sensor's own coordinates" do
    fake = use_source(ClimateTestHelpers::FakeOutdoorSource.new(rows: rows))

    Climate::OutdoorPollJob.perform_now

    assert_in_delta 55.9467, fake.calls.first[:latitude], 0.0001
    assert_in_delta(-3.1903, fake.calls.first[:longitude], 0.0001)
  end

  test "re-running does not multiply rows" do
    use_source(ClimateTestHelpers::FakeOutdoorSource.new(rows: rows))
    Climate::OutdoorPollJob.perform_now

    assert_no_difference -> { Climate::Reading.count } do
      3.times { Climate::OutdoorPollJob.perform_now }
    end
  end

  test "a run after an outage backfills the gap with no backfill code" do
    # The whole reason Open-Meteo was chosen: past_days re-serves recent history,
    # so the next successful poll repairs whatever the outage lost.
    use_source(ClimateTestHelpers::FakeOutdoorSource.new(rows: rows(count: 6)))
    Climate::OutdoorPollJob.perform_now
    sensor = outdoor_climate_sensor
    sensor.readings.chronological.to_a[2..3].each(&:destroy)

    assert_equal 4, sensor.readings.count

    Climate::OutdoorPollJob.perform_now

    assert_equal 6, sensor.readings.count
  end

  test "records last_polled_at and clears last_error on success" do
    sensor = outdoor_climate_sensor
    sensor.update_columns(last_error: "yesterday's failure")
    use_source(ClimateTestHelpers::FakeOutdoorSource.new(rows: rows))

    Climate::OutdoorPollJob.perform_now
    sensor.reload

    assert_not_nil sensor.last_polled_at
    assert_nil sensor.last_error
  end

  test "a fetch failure is recorded, not raised" do
    sensor = outdoor_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: 1.hour.ago)
    use_source(ClimateTestHelpers::FakeOutdoorSource.new(rows: Climate::OpenMeteoClient::Error.new("502")))

    Climate::OutdoorPollJob.perform_now

    assert_match(/502/, sensor.reload.last_error)
  end

  test "a failure is not reported while the outdoor line is still current" do
    # Open-Meteo's free tier sheds load with the odd 503 and the next successful
    # poll re-serves the window, so one failure is nothing to wake anybody for.
    sensor = outdoor_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: 1.hour.ago)
    use_source(ClimateTestHelpers::FakeOutdoorSource.new(rows: Climate::OpenMeteoClient::Error.new("503")))

    notices = capture_honeybadger_notices { Climate::OutdoorPollJob.perform_now }

    assert_empty notices
  end

  test "a failure is reported once the outdoor line has been missing for a day" do
    sensor = outdoor_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: 25.hours.ago)
    use_source(ClimateTestHelpers::FakeOutdoorSource.new(rows: Climate::OpenMeteoClient::Error.new("503")))

    notices = capture_honeybadger_notices { Climate::OutdoorPollJob.perform_now }

    assert_equal 1, notices.size
    assert_in_delta 25.hours.ago.to_i,
                    notices.first.last[:context][:latest_reading_at].to_i, 5
  end

  test "a failure is reported when the sensor has never had a reading" do
    outdoor_climate_sensor
    use_source(ClimateTestHelpers::FakeOutdoorSource.new(rows: Climate::OpenMeteoClient::Error.new("503")))

    notices = capture_honeybadger_notices { Climate::OutdoorPollJob.perform_now }

    assert_equal 1, notices.size
  end

  test "skips an outdoor sensor that has been deactivated" do
    outdoor_climate_sensor.update!(active: false)
    fake = use_source(ClimateTestHelpers::FakeOutdoorSource.new(rows: rows))

    Climate::OutdoorPollJob.perform_now

    assert_empty fake.calls
  end

  test "does not touch the govee sensors" do
    govee = create_climate_sensor
    use_source(ClimateTestHelpers::FakeOutdoorSource.new(rows: rows))

    Climate::OutdoorPollJob.perform_now

    assert_equal 0, govee.readings.count
  end

  test "needs no api key configured" do
    ENV.delete("CLIMATE_GOVEE_API_KEY")
    use_source(ClimateTestHelpers::FakeOutdoorSource.new(rows: rows))

    Climate::OutdoorPollJob.perform_now

    assert_operator outdoor_climate_sensor.readings.count, :>, 0
  end
end
