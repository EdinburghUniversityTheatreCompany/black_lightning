class CreateClimateSensors < ActiveRecord::Migration[8.1]
  # A source of temperature/humidity readings for the crypt climate monitor.
  # Both the Govee thermo-hygrometers and the outdoor weather feed are rows in
  # this table, distinguished by +source+, so the charts, tiles and range query
  # are one code path rather than an indoor branch and an outdoor branch.
  def change
    create_table :climate_sensors do |t|
      t.string :source, null: false, default: "govee"      # govee | open_meteo
      t.string :placement, null: false, default: "indoor"  # indoor | outdoor

      # Govee's own device identifier (a MAC-like string) and model code.
      # Null for a weather feed, which is located by lat/lon instead.
      t.string :external_id
      t.string :sku

      t.string :display_name, null: false
      t.string :location

      # DELIBERATELY nullable with no default. Govee does not document the unit
      # of sensorTemperature and it is widely reported as Fahrenheit even when
      # the app shows Celsius, so the ingest path refuses to write until an
      # operator has confirmed it against the device display. Defaulting this to
      # "celsius" would be the silent-corruption bug, not a convenience.
      t.string :temperature_unit
      t.datetime :unit_verified_at

      # Also deliberately false: a freshly discovered sensor must be reviewed
      # (named, placed, unit-verified) before it starts writing history.
      t.boolean :active, null: false, default: false

      t.decimal :latitude, precision: 9, scale: 6   # outdoor sources only
      t.decimal :longitude, precision: 9, scale: 6

      t.integer :position, null: false, default: 0  # chart/tile ordering

      t.datetime :last_polled_at
      t.string :last_error, limit: 500

      t.timestamps
    end

    # Discovery upserts on this pair, so re-running it must not duplicate a
    # known device. Both columns are needed: external_id is null for open_meteo.
    add_index :climate_sensors, %i[source external_id], unique: true
    add_index :climate_sensors, :active
  end
end
