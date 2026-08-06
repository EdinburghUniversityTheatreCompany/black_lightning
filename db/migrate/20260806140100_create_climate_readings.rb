class CreateClimateReadings < ActiveRecord::Migration[8.1]
  # One temperature/humidity sample from one sensor at one instant.
  #
  # The Govee API has no history endpoint — it serves "now" and nothing else —
  # so this table IS the history, accumulated by the poll job. Nothing before
  # the first poll can ever be recovered.
  def change
    create_table :climate_readings do |t|
      # bigint is correct: climate_sensors is a new table. The project's
      # integer-PK rule only applies to FKs pointing at the legacy tables.
      # index: false because the composite unique index below leads with
      # sensor_id and serves as its prefix — a second index on sensor_id alone
      # would be dead weight on the most-written table in the app.
      t.references :sensor, null: false, index: false,
                            foreign_key: { to_table: :climate_sensors }

      t.datetime :recorded_at, null: false

      t.decimal :temperature_c, precision: 5, scale: 2
      t.decimal :relative_humidity, precision: 5, scale: 2
      t.decimal :dew_point_c, precision: 5, scale: 2

      # Exactly what the API returned, plus the unit we BELIEVED at write time.
      # This is what makes a wrong temperature_unit a backfill rather than a
      # permanent hole: the conversion can be redone from the raw value.
      t.decimal :raw_temperature, precision: 7, scale: 2
      t.string :raw_temperature_unit, limit: 1 # "C" | "F"

      t.timestamps
    end

    # Polling is idempotent through this index: Govee readings are floored to a
    # fixed bucket and the outdoor window is re-upserted wholesale every hour,
    # so a retried job, a manual poll and a double-fired schedule all collide
    # here instead of duplicating. It must exist before the first poll runs —
    # MySQL's upsert has no way to name a target index, it collides on whatever
    # unique index is there.
    add_index :climate_readings, %i[sensor_id recorded_at], unique: true
  end
end
