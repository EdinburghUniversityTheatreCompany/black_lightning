module Climate
  def self.table_name_prefix
    "climate_"
  end

  # Below this margin (°C) between air temperature and dew point, condensation is
  # a live risk: roughly 80% humidity at the surface, where mould starts. Lives
  # here, not in ClimateHelper, because the risk services read it too.
  CONDENSATION_RISK_MARGIN = 3.0

  # The outdoor-weather seam: another source (Met Office DataHub, NOAA METAR) is
  # one client class answering #hourly_series plus one entry here.
  OUTDOOR_SOURCES = {
    Sensor::SOURCE_OPEN_METEO => -> { OpenMeteoClient.new }
  }.freeze

  def self.outdoor_client_for(source)
    builder = OUTDOOR_SOURCES[source]
    raise ArgumentError, "No outdoor weather client for source #{source.inspect}" if builder.nil?

    builder.call
  end
end
