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

  test "latest_reading returns the most recent by recorded_at, not by insertion order" do
    sensor = create_climate_sensor
    create_climate_reading(sensor: sensor, recorded_at: 2.hours.ago, temperature_c: 9.0)
    newest = create_climate_reading(sensor: sensor, recorded_at: 10.minutes.ago, temperature_c: 11.0)
    create_climate_reading(sensor: sensor, recorded_at: 5.hours.ago, temperature_c: 8.0)

    assert_equal newest, sensor.latest_reading
  end

  test "stale? waits a day on a Govee sensor, hours on the outdoor feed, and fires with no readings" do
    # Crypt readings arrive whenever somebody exports a CSV, so minutes-scale
    # thresholds would mark them stale essentially always.
    recent = create_climate_sensor
    create_climate_reading(sensor: recent, recorded_at: 4.hours.ago)
    old = create_climate_sensor
    create_climate_reading(sensor: old, recorded_at: 30.hours.ago)
    outdoor = outdoor_climate_sensor
    create_climate_reading(sensor: outdoor, recorded_at: 4.hours.ago)

    assert_not recent.stale?
    assert_predicate old, :stale?
    assert_predicate outdoor, :stale?
    assert_predicate create_climate_sensor, :stale?
  end

  test "in_display_order puts indoor sensors before the outdoor line" do
    outdoor = outdoor_climate_sensor
    second = create_climate_sensor(display_name: "Crypt, south wall", position: 2)
    first = create_climate_sensor(display_name: "Crypt, north wall", position: 1)

    assert_equal [ first, second, outdoor ], Climate::Sensor.in_display_order.to_a
  end

  test "outdoor_source! creates one active row at Bedlam" do
    outdoor = Climate::Sensor.outdoor_source!

    assert_predicate outdoor, :outdoor?
    assert_predicate outdoor, :active?
    assert_in_delta 55.9467, outdoor.latitude.to_f, 0.001
    assert_in_delta(-3.1903, outdoor.longitude.to_f, 0.001)
  end

  test "outdoor_source! leaves an operator's corrected coordinates alone" do
    # find_or_create_by only assigns on create, so the hourly poll cannot revert
    # a corrected location.
    Climate::Sensor.outdoor_source!.update!(latitude: 55.9500, display_name: "Outside (roof)")

    reloaded = assert_no_difference(-> { Climate::Sensor.count }) { Climate::Sensor.outdoor_source! }

    assert_in_delta 55.9500, reloaded.latitude.to_f, 0.0001
    assert_equal "Outside (roof)", reloaded.display_name
  end

  test "the outdoor feed cannot be marked as being in the crypt" do
    sensor = outdoor_climate_sensor
    sensor.in_crypt = true

    assert_not sensor.valid?
    assert sensor.errors[:in_crypt].present?
  end

  test "the in_crypt scope returns only the ticked sensors" do
    crypt = create_climate_sensor(display_name: "Crypt", in_crypt: true)
    create_climate_sensor(display_name: "Dressing room", in_crypt: false)

    assert_equal [ crypt.id ], Climate::Sensor.in_crypt.pluck(:id)
  end
end
