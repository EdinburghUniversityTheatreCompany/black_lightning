class DropClimateSensorUnitVerification < ActiveRecord::Migration[8.1]
  # Readings now arrive by CSV export rather than by polling the Govee API, and
  # the export names its own unit in the header ("Temperature_Celsius"), so the
  # importer reads it per file instead of an operator confirming it per sensor.
  # That removes the whole reason these two columns existed.
  #
  # `external_id` and `sku` go with them: they identified a device to the API,
  # and the CSV carries no device identifier at all — the operator picks the
  # sensor a file belongs to.
  def change
    # safety_assured: strong_migrations blocks remove_column because running code
    # may still select it. Nothing has ever deployed against these columns — the
    # climate tables landed in the same unreleased series of commits — so there is
    # no old process to break.
    safety_assured do
      remove_column :climate_sensors, :temperature_unit, :string
      remove_column :climate_sensors, :unit_verified_at, :datetime
      remove_index :climate_sensors, column: %i[source external_id],
                   unique: true, name: "index_climate_sensors_on_source_and_external_id"
      remove_column :climate_sensors, :external_id, :string
      remove_column :climate_sensors, :sku, :string
    end
  end
end
