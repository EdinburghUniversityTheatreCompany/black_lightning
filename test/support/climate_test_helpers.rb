# Builders and fakes for the climate monitor tests: database seed helpers for
# sensors and readings, permission grants, and fake external clients (Govee,
# outdoor weather). External services are always faked through the +http:+ or
# builder seams — this suite has no mocking library.
module ClimateTestHelpers
  # --- Database seed helpers -------------------------------------------------

  def create_climate_sensor(display_name: "Crypt, north wall", source: Climate::Sensor::SOURCE_GOVEE,
                            placement: Climate::Sensor::PLACEMENT_INDOOR,
                            external_id: nil, sku: "H5179",
                            temperature_unit: Climate::Sensor::UNIT_CELSIUS,
                            active: true, location: nil, position: 0,
                            latitude: nil, longitude: nil)
    external_id ||= "AA:BB:CC:DD:#{format('%02X', rand(256))}:#{format('%02X', rand(256))}" if source == Climate::Sensor::SOURCE_GOVEE

    Climate::Sensor.create!(
      display_name: display_name, source: source, placement: placement,
      external_id: external_id, sku: (sku if source == Climate::Sensor::SOURCE_GOVEE),
      temperature_unit: temperature_unit,
      unit_verified_at: (Time.current if temperature_unit.present?),
      active: active, location: location, position: position,
      latitude: latitude, longitude: longitude
    )
  end

  # The one outdoor row, through the same ensure the poll job uses. Never build
  # a second: the unique index on (source, external_id) allows only one row with
  # a nil external_id.
  def outdoor_climate_sensor = Climate::Sensor.outdoor_source!

  def create_climate_reading(sensor:, recorded_at: Time.current, temperature_c: 12.0,
                             relative_humidity: 78.0, dew_point_c: nil,
                             raw_temperature: nil, raw_temperature_unit: "C")
    dew_point_c ||= Climate::DewPoint.celsius(temperature_c: temperature_c,
                                              relative_humidity: relative_humidity)

    Climate::Reading.create!(
      sensor: sensor, recorded_at: recorded_at,
      temperature_c: temperature_c, relative_humidity: relative_humidity,
      dew_point_c: dew_point_c,
      raw_temperature: raw_temperature || temperature_c,
      raw_temperature_unit: raw_temperature_unit
    )
  end

  # --- Permission grants -----------------------------------------------------

  # :read, :climate — sees the dashboard, cannot touch sensor configuration.
  def grant_climate_read_permission(user)
    role = ::Role.find_by(name: "Climate Viewer") || ::Role.create!(name: "Climate Viewer").tap do |r|
      r.permissions << Admin::Permission.create(action: "read", subject_class: "climate")
    end
    user.add_role("Climate Viewer")
    role
  end

  # :manage, :climate — CanCan's :manage matches any action, so this implies
  # :read as well; the tests assert that rather than granting both.
  def grant_climate_manage_permission(user)
    role = ::Role.find_by(name: "Climate Manager") || ::Role.create!(name: "Climate Manager").tap do |r|
      r.permissions << Admin::Permission.create(action: "manage", subject_class: "climate")
    end
    user.add_role("Climate Manager")
    role
  end

  # --- Fake external clients -------------------------------------------------

  # Stands in for Climate::GoveeClient. Queue devices and per-device states;
  # raise by queueing an Exception, the same convention as FakeHttp.
  class FakeGovee
    attr_reader :state_calls, :device_calls
    attr_accessor :rate_limit_remaining

    def initialize(devices: [], states: {})
      @devices = devices
      @states = states
      @state_calls = []
      @device_calls = 0
      @rate_limit_remaining = 9_000
    end

    def devices
      @device_calls += 1
      raise @devices if @devices.is_a?(Exception)

      @devices
    end

    def state(sku:, external_id:)
      @state_calls << { sku: sku, external_id: external_id }
      result = @states.fetch(external_id) { raise "FakeGovee has no state queued for #{external_id}" }
      raise result if result.is_a?(Exception)

      result
    end
  end

  # Stands in for Climate::OpenMeteoClient.
  class FakeOutdoorSource
    attr_reader :calls

    def initialize(rows: [])
      @rows = rows
      @calls = []
    end

    def hourly_series(latitude:, longitude:, **options)
      @calls << { latitude: latitude, longitude: longitude, **options }
      raise @rows if @rows.is_a?(Exception)

      @rows
    end
  end
end
