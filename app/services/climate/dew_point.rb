module Climate
  ##
  # Dew point from temperature + relative humidity, by the Magnus formula.
  #
  # This is the number the crypt monitor exists for: condensation forms on any
  # surface at or below the dew point, so "temperature minus dew point" is the
  # damp-risk margin, and a dew point tracking the air temperature means the
  # room is at saturation.
  #
  # Coefficients are Alduchov & Eskridge (1996) — max error about 0.1 °C over
  # -40..+50 °C, better than the older Tetens 17.27/237.7 pair for the cold,
  # damp end we actually care about.
  module DewPoint
    A = 17.625
    B = 243.04 # °C

    # γ = ln(RH/100) + (A·T)/(B+T);  Td = (B·γ)/(A−γ)
    #
    # Returns nil rather than a number for anything unusable, because the
    # callers write straight into a decimal column: ln(0) is -Infinity, which
    # would cast to a silently wrong stored value instead of raising.
    def self.celsius(temperature_c:, relative_humidity:)
      return nil if temperature_c.nil? || relative_humidity.nil?

      humidity = relative_humidity.to_f
      return nil unless humidity.positive?

      # A sensor reading above 100 % is miscalibrated, not supersaturated air.
      # Clamping keeps the guarantee every consumer relies on: Td <= T.
      humidity = 100.0 if humidity > 100.0

      temperature = temperature_c.to_f
      gamma = Math.log(humidity / 100.0) + ((A * temperature) / (B + temperature))
      ((B * gamma) / (A - gamma)).round(2)
    end
  end
end
