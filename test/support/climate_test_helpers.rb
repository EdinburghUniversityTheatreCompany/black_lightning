# Seed helpers and permission grants for the climate tests.
module ClimateTestHelpers
  include HoneybadgerTestHelpers

  # An indoor Govee sensor: source and placement take the column defaults.
  def create_climate_sensor(display_name: "Crypt, north wall", active: true, location: nil,
                            position: 0, in_crypt: false)
    Climate::Sensor.create!(display_name: display_name, active: active, location: location,
                            position: position, in_crypt: in_crypt)
  end

  def outdoor_climate_sensor = Climate::Sensor.outdoor_source!

  def create_climate_reading(sensor:, recorded_at: Time.current, temperature_c: 12.0,
                             relative_humidity: 78.0, dew_point_c: nil)
    dew_point_c ||= Climate::DewPoint.celsius(temperature_c: temperature_c,
                                              relative_humidity: relative_humidity)

    Climate::Reading.create!(
      sensor: sensor, recorded_at: recorded_at,
      temperature_c: temperature_c, relative_humidity: relative_humidity,
      dew_point_c: dew_point_c, raw_temperature: temperature_c, raw_temperature_unit: "C"
    )
  end

  def grant_climate_read_permission(user)
    role = ::Role.find_by(name: "Climate Viewer") || ::Role.create!(name: "Climate Viewer").tap do |r|
      r.permissions << Admin::Permission.create(action: "read", subject_class: "climate")
    end
    user.add_role("Climate Viewer")
    role
  end

  # CanCan's :manage matches any action, so this implies :read; tests assert
  # that rather than granting both.
  def grant_climate_manage_permission(user)
    role = ::Role.find_by(name: "Climate Manager") || ::Role.create!(name: "Climate Manager").tap do |r|
      r.permissions << Admin::Permission.create(action: "manage", subject_class: "climate")
    end
    user.add_role("Climate Manager")
    role
  end
end
