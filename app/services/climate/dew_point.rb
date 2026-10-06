module Climate
  ##
  # Dew point from temperature and relative humidity, by the Magnus formula with
  # Alduchov & Eskridge (1996) coefficients (max error ~0.1 °C over -40..+50 °C).
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

      # Above 100 % is miscalibration; clamping keeps Td <= T, which consumers rely on.
      humidity = 100.0 if humidity > 100.0

      temperature = temperature_c.to_f
      gamma = Math.log(humidity / 100.0) + ((A * temperature) / (B + temperature))
      ((B * gamma) / (A - gamma)).round(2)
    end
  end
end
