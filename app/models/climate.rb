module Climate
  # ActiveRecord models in this namespace live in climate_* tables
  # (e.g. Climate::Sensor -> climate_sensors).
  def self.table_name_prefix
    "climate_"
  end
end
