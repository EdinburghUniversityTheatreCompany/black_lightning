class AddInCryptToClimateSensors < ActiveRecord::Migration[8.1]
  # Which sensors are "the crypt" has to be stored rather than inferred:
  # placement already separates indoor from outdoor, but a dressing-room or
  # upstairs sensor is indoor too and would poison a crypt-only worst case.
  #
  # Backfilling here is safe, unlike Sensor.outdoor_source! — that had to be
  # ensured at runtime because test and CI databases are schema-LOADED, so a
  # migration would leave every environment except production without the row.
  # A backfill only has to touch rows that already exist, and those have none.
  def change
    add_column :climate_sensors, :in_crypt, :boolean, default: false, null: false

    reversible do |direction|
      direction.up do
        # strong_migrations can't inspect what happens inside execute; this is
        # a plain UPDATE against a handful of sensor rows, not a bulk backfill.
        safety_assured do
          execute(<<~SQL.squish)
            UPDATE climate_sensors
            SET in_crypt = TRUE
            WHERE placement = 'indoor' AND source = 'govee'
          SQL
        end
      end
    end
  end
end
