module Climate
  # ActiveRecord models in this namespace live in climate_* tables
  # (e.g. Climate::Sensor -> climate_sensors).
  def self.table_name_prefix
    "climate_"
  end

  # Below this many degrees between the air temperature and its dew point,
  # condensation is a live risk rather than a theoretical one. This is the
  # number the crypt monitor exists to watch — roughly 80% humidity at the
  # surface, which is where mould starts to grow.
  #
  # Lives here rather than in ClimateHelper because the risk services read it
  # too, and a service reaching into a view helper is the wrong direction.
  CONDENSATION_RISK_MARGIN = 3.0

  # The outdoor-weather seam. Swapping Open-Meteo for Met Office DataHub or the
  # NOAA METAR feed at Edinburgh Airport is one new client class answering
  # #hourly_series, plus one entry here. No change to the job, the models or
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
