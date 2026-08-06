module Climate
  # ActiveRecord models in this namespace live in climate_* tables
  # (e.g. Climate::Sensor -> climate_sensors).
  def self.table_name_prefix
    "climate_"
  end

  # The outdoor-weather seam. Swapping Open-Meteo for Met Office DataHub or the
  # NOAA METAR feed at Edinburgh Airport is one new client class answering
  # #hourly_series, plus one entry here — no change to the job, the models or
  # the dashboard.
  OUTDOOR_SOURCES = {
    Sensor::SOURCE_OPEN_METEO => -> { OpenMeteoClient.new }
  }.freeze

  def self.outdoor_client_for(source)
    builder = OUTDOOR_SOURCES[source]
    raise ArgumentError, "No outdoor weather client for source #{source.inspect}" if builder.nil?

    builder.call
  end
end
