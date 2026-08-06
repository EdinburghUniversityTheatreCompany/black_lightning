require "test_helper"

class Climate::SensorTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  test "an open_meteo sensor requires coordinates" do
    sensor = Climate::Sensor.new(display_name: "Outside",
                                 source: Climate::Sensor::SOURCE_OPEN_METEO,
                                 placement: Climate::Sensor::PLACEMENT_OUTDOOR)

    assert_not sensor.valid?
    assert sensor.errors[:latitude].present?
    assert sensor.errors[:longitude].present?
  end

  test "rejects an unknown source or placement" do
    sensor = create_climate_sensor
    sensor.source = "guesswork"

    assert_not sensor.valid?

    sensor = create_climate_sensor
    sensor.placement = "somewhere"

    assert_not sensor.valid?
  end

  test "latest_reading returns the most recent by recorded_at, not by insertion order" do
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: 2.hours.ago, temperature_c: 9.0)
    newest = create_climate_reading(sensor: sensor, recorded_at: 10.minutes.ago, temperature_c: 11.0)
    create_climate_reading(sensor: sensor, recorded_at: 5.hours.ago, temperature_c: 8.0)

    assert_equal newest, sensor.latest_reading
  end

  test "stale? is false for a sensor imported recently" do
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: 2.hours.ago)

    assert_not sensor.stale?
  end

  test "stale? is true once a govee sensor's last import is more than a day old" do
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: 30.hours.ago)

    assert_predicate sensor, :stale?
  end

  test "an imported sensor gets a longer staleness window than the hourly outdoor feed" do
    # Crypt readings arrive whenever somebody exports a CSV, so minutes-scale
    # thresholds would mark them stale essentially always.
    outdoor = outdoor_climate_sensor
    create_climate_reading(sensor: outdoor, recorded_at: 90.minutes.ago)

    assert_not outdoor.stale?
    assert_operator create_climate_sensor.stale_after, :>, outdoor.stale_after
  end

  test "a sensor with no readings at all is stale" do
    assert_predicate create_climate_sensor, :stale?
  end

  test "readings are removed with the sensor" do
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor)

    assert_difference -> { Climate::Reading.count }, -1 do
      sensor.destroy
    end
  end

  test "in_display_order puts indoor sensors before the outdoor line" do
    outdoor = outdoor_climate_sensor
    second = create_climate_sensor(display_name: "Crypt, south wall", position: 2)
    first = create_climate_sensor(display_name: "Crypt, north wall", position: 1)

    assert_equal [ first, second, outdoor ], Climate::Sensor.in_display_order.to_a
  end

  test "outdoor_source! creates one active, unit-verified row at Bedlam" do
    outdoor = Climate::Sensor.outdoor_source!

    assert_predicate outdoor, :outdoor?
    assert_predicate outdoor, :active?
    assert_in_delta 55.9467, outdoor.latitude.to_f, 0.001
    assert_in_delta(-3.1903, outdoor.longitude.to_f, 0.001)
  end

  test "outdoor_source! is idempotent and never a second row" do
    first = Climate::Sensor.outdoor_source!

    assert_no_difference -> { Climate::Sensor.count } do
      assert_equal first, Climate::Sensor.outdoor_source!
    end
  end

  test "outdoor_source! leaves an operator's corrected coordinates alone" do
    # find_or_create_by only assigns on create — otherwise the hourly poll job
    # would silently revert a corrected location on every run.
    Climate::Sensor.outdoor_source!.update!(latitude: 55.9500, display_name: "Outside (roof)")

    reloaded = Climate::Sensor.outdoor_source!

    assert_in_delta 55.9500, reloaded.latitude.to_f, 0.0001
    assert_equal "Outside (roof)", reloaded.display_name
  end
end
