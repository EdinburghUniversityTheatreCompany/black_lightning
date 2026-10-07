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

  def grant_climate_read_permission(user) = grant_permission(user, "Climate Viewer", "read", "climate")

  # CanCan's :manage matches any action, so this implies :read; tests assert
  # that rather than granting both.
  def grant_climate_manage_permission(user) = grant_permission(user, "Climate Manager", "manage", "climate")

  def grant_backend(user) = grant_permission(user, "Backend", "access", "backend")

  private

  def grant_permission(user, role_name, action, subject)
    role = ::Role.find_by(name: role_name) || ::Role.create!(name: role_name).tap do |r|
      r.permissions << Admin::Permission.create(action: action, subject_class: subject)
    end
    user.add_role(role_name)
    role
  end
end
