module Climate
  def self.table_name_prefix
    "climate_"
  end

  # Below this margin (°C) between air temperature and dew point, condensation is
  # a live risk: roughly 80% humidity at the surface, where mould starts. Lives
  # here, not in ClimateHelper, because the risk services read it too.
  CONDENSATION_RISK_MARGIN = 3.0
end
