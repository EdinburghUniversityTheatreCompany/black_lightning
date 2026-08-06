module Climate
  ##
  # Dew point from temperature + relative humidity, by the Magnus formula.
  # Condensation forms at or below it, so "temperature minus dew point" is the
  # damp-risk margin this whole feature exists to watch.
  #
  # Coefficients are Alduchov & Eskridge (1996), max error about 0.1 °C over
  # -40..+50 °C, better than the older Tetens 17.27/237.7 pair at the cold, damp
  # end we care about.
  module DewPoint
    A = 17.625
    B = 243.04 # °C

    # γ = ln(RH/100) + (A·T)/(B+T);  Td = (B·γ)/(A−γ)
    #
    # nil for anything unusable, because callers write straight into a decimal
    # column: ln(0) is -Infinity, which casts to a silently wrong value.
    def self.celsius(temperature_c:, relative_humidity:)
      return nil if temperature_c.nil? || relative_humidity.nil?

      humidity = relative_humidity.to_f
      return nil unless humidity.positive?

      # Above 100 % is miscalibration, not supersaturated air. Clamping keeps
      # the guarantee every consumer relies on: Td <= T.
      humidity = 100.0 if humidity > 100.0

      temperature = temperature_c.to_f
      gamma = Math.log(humidity / 100.0) + ((A * temperature) / (B + temperature))
      ((B * gamma) / (A - gamma)).round(2)
    end
  end
end
