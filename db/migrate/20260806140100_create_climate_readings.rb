class CreateClimateReadings < ActiveRecord::Migration[8.1]
  # One temperature/humidity sample from one sensor at one instant.
  #
  # The Govee API has no history endpoint — it serves "now" and nothing else —
  # so this table IS the history, accumulated by the poll job. Nothing before
  # the first poll can ever be recovered.
  def change
    create_table :climate_readings do |t|
      # index: false because the composite unique index below leads with
      # sensor_id and serves as its prefix; a second index on sensor_id alone
      # would be dead weight on the most-written table in the app.
      # on_delete: :cascade matches the model's dependent: :delete_all — an
      # orphaned reading is a temperature from nowhere.
      t.references :sensor, null: false, index: false,
                            foreign_key: { to_table: :climate_sensors, on_delete: :cascade }

      t.datetime :recorded_at, null: false

      t.decimal :temperature_c, precision: 5, scale: 2
      t.decimal :relative_humidity, precision: 5, scale: 2
      t.decimal :dew_point_c, precision: 5, scale: 2

      # What the API returned, plus the unit we BELIEVED at write time — which
      # is what makes a wrong temperature_unit a backfill rather than a
      # permanent hole.
      t.decimal :raw_temperature, precision: 7, scale: 2
      t.string :raw_temperature_unit, limit: 1 # "C" | "F"

      t.timestamps

      # What makes polling idempotent, so it must exist before the first poll:
      # MySQL's upsert cannot name a target index, it collides on whatever
      # unique index is there.
      #
      # Declared inside create_table, not as a separate add_index, or the
      # migration is irreversible — a separate add_index reverses as a
      # remove_index BEFORE the drop_table, and MySQL refuses to drop an index a
      # foreign key still needs.
      t.index %i[sensor_id recorded_at], unique: true
    end
  end
end
