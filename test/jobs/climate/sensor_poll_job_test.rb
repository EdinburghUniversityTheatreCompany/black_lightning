require "test_helper"

class Climate::SensorPollJobTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  setup do
    @original_builder = Climate::SensorPollJob.client_builder
    @original_key = ENV.fetch("CLIMATE_GOVEE_API_KEY", nil)
    ENV["CLIMATE_GOVEE_API_KEY"] = "test-key"
  end

  teardown do
    # class_attribute's writer defines a singleton on whatever it is set on, so
    # a seam left in place would stick for the rest of the process and leak into
    # every later test in this worker.
    Climate::SensorPollJob.client_builder = @original_builder
    @original_key.nil? ? ENV.delete("CLIMATE_GOVEE_API_KEY") : ENV["CLIMATE_GOVEE_API_KEY"] = @original_key
  end

  def use_govee(fake)
    Climate::SensorPollJob.client_builder = -> { fake }
    fake
  end

  def state(temperature: 12.4, humidity: 78, online: true)
    Climate::GoveeClient::State.new(raw_temperature: temperature, relative_humidity: humidity,
                                    online: online, fetched_at: Time.current)
  end

  test "no-ops and says so when no Govee key is configured" do
    ENV.delete("CLIMATE_GOVEE_API_KEY")
    sensor = create_climate_sensor
    fake = use_govee(ClimateTestHelpers::FakeGovee.new)

    Climate::SensorPollJob.perform_now

    assert_empty fake.state_calls
    assert_equal 0, sensor.readings.count
  end

  test "writes one reading per active sensor" do
    first = create_climate_sensor(display_name: "North", external_id: "AA:01")
    second = create_climate_sensor(display_name: "South", external_id: "AA:02")
    use_govee(ClimateTestHelpers::FakeGovee.new(states: { "AA:01" => state(temperature: 11.0),
                                                          "AA:02" => state(temperature: 13.0) }))

    Climate::SensorPollJob.perform_now

    assert_in_delta 11.0, first.readings.sole.temperature_c.to_f, 0.001
    assert_in_delta 13.0, second.readings.sole.temperature_c.to_f, 0.001
  end

  test "ignores inactive sensors" do
    sensor = create_climate_sensor(active: false)
    fake = use_govee(ClimateTestHelpers::FakeGovee.new)

    Climate::SensorPollJob.perform_now

    assert_empty fake.state_calls
    assert_equal 0, sensor.readings.count
  end

  test "never polls the outdoor source" do
    # It has no Govee device id; asking Govee for it would 400 every ten minutes.
    outdoor = outdoor_climate_sensor
    fake = use_govee(ClimateTestHelpers::FakeGovee.new)

    Climate::SensorPollJob.perform_now

    assert_empty fake.state_calls
    assert_equal 0, outdoor.readings.count
  end

  test "skips a sensor whose temperature unit has not been verified" do
    # The unit gate reaching all the way out to the job: no reading is better
    # than a reading in the wrong unit.
    sensor = create_climate_sensor(temperature_unit: nil)
    use_govee(ClimateTestHelpers::FakeGovee.new(states: { sensor.external_id => state }))

    Climate::SensorPollJob.perform_now

    assert_equal 0, sensor.readings.count
    assert_match(/unit not verified/i, sensor.reload.last_error)
  end

  test "skips a sensor Govee reports as offline" do
    sensor = create_climate_sensor
    use_govee(ClimateTestHelpers::FakeGovee.new(states: { sensor.external_id => state(online: false) }))

    Climate::SensorPollJob.perform_now

    assert_equal 0, sensor.readings.count
    assert_match(/offline/i, sensor.reload.last_error)
  end

  test "one sensor's failure does not stop the others" do
    failing = create_climate_sensor(display_name: "Broken", external_id: "AA:01")
    working = create_climate_sensor(display_name: "Fine", external_id: "AA:02")
    use_govee(ClimateTestHelpers::FakeGovee.new(
                states: { "AA:01" => Climate::GoveeClient::Error.new("device gone"),
                          "AA:02" => state(temperature: 13.0) }
              ))

    capture_honeybadger_notices { Climate::SensorPollJob.perform_now }

    assert_equal 0, failing.readings.count
    assert_equal 1, working.readings.count
  end

  test "reports a single sensor's failure to Honeybadger" do
    sensor = create_climate_sensor
    use_govee(ClimateTestHelpers::FakeGovee.new(
                states: { sensor.external_id => Climate::GoveeClient::Error.new("device gone") }
              ))

    notices = capture_honeybadger_notices { Climate::SensorPollJob.perform_now }

    assert_equal 1, notices.size
    assert_match(/device gone/, sensor.reload.last_error)
  end

  test "an auth failure abandons the cycle and is reported once" do
    # The key is shared by every sensor, so working through the rest of the list
    # would just be N identical 401s.
    create_climate_sensor(display_name: "North", external_id: "AA:01")
    create_climate_sensor(display_name: "South", external_id: "AA:02")
    use_govee(ClimateTestHelpers::FakeGovee.new(
                states: { "AA:01" => Climate::GoveeClient::AuthError.new("bad key"),
                          "AA:02" => state }
              ))

    notices = capture_honeybadger_notices { Climate::SensorPollJob.perform_now }

    assert_equal 1, notices.size
    assert_equal 0, Climate::Reading.count
  end

  test "records last_polled_at and clears last_error on success" do
    sensor = create_climate_sensor
    sensor.update_columns(last_error: "something old")
    use_govee(ClimateTestHelpers::FakeGovee.new(states: { sensor.external_id => state }))

    Climate::SensorPollJob.perform_now
    sensor.reload

    assert_not_nil sensor.last_polled_at
    assert_nil sensor.last_error
  end

  test "an implausible reading is recorded as an error, not stored" do
    sensor = create_climate_sensor
    use_govee(ClimateTestHelpers::FakeGovee.new(
                states: { sensor.external_id => state(temperature: 240.0) }
              ))

    capture_honeybadger_notices { Climate::SensorPollJob.perform_now }

    assert_equal 0, sensor.readings.count
    assert_match(/outside/, sensor.reload.last_error)
  end

  test "consecutive cycles inside one bucket keep a single row" do
    sensor = create_climate_sensor
    use_govee(ClimateTestHelpers::FakeGovee.new(states: { sensor.external_id => state }))

    3.times { Climate::SensorPollJob.perform_now }

    assert_equal 1, sensor.readings.count
  end

  test "asks Govee for nothing when there are no active sensors" do
    fake = use_govee(ClimateTestHelpers::FakeGovee.new)

    Climate::SensorPollJob.perform_now

    assert_empty fake.state_calls
  end
end
