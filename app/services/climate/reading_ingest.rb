module Climate
  ##
  # The single write path into climate_readings: unit conversion, dew point,
  # the plausibility guard and the idempotent upsert. Nothing else should create
  # a Climate::Reading.
  class ReadingIngest
    # Govee sends no timestamp, so we assign one, floored to a fixed bucket —
    # which is what gives the unique index something to enforce when a retried
    # job, a manual poll and a double-fired schedule all land together.
    BUCKET_SECONDS = 600

    # The second net under the unverified-unit rule; an Edinburgh basement
    # reaches neither bound.
    #
    # Its reach, honestly: a true temperature above ~10 °C misread as Fahrenheit
    # lands above 50 and is caught (12 -> 53.6, 20 -> 68), but below ~10 °C it
    # slips through. Not a substitute for the unit gate.
    PLAUSIBLE_CELSIUS = (-20.0..50.0)
    PLAUSIBLE_HUMIDITY = (0.0..100.0)

    class Error < StandardError; end
    class UnverifiedUnitError < Error; end
    class ImplausibleReading < Error; end

    def self.bucket(time, seconds: BUCKET_SECONDS)
      Time.zone.at((time.to_i / seconds) * seconds)
    end

    # +raw_temperature+ is verbatim from the API, in whatever unit the operator
    # verified for this sensor.
    def self.record_govee!(sensor:, raw_temperature:, relative_humidity:, at: Time.current)
      unless sensor.unit_verified?
        raise UnverifiedUnitError,
              "#{sensor.display_name} has no verified temperature unit; refusing to guess"
      end

      celsius = to_celsius(raw_temperature, sensor)
      validate!(sensor, celsius, relative_humidity)

      write([ row_for(sensor: sensor, recorded_at: bucket(at), temperature_c: celsius,
                      relative_humidity: relative_humidity,
                      dew_point_c: DewPoint.celsius(temperature_c: celsius,
                                                    relative_humidity: relative_humidity),
                      raw_temperature: raw_temperature,
                      raw_temperature_unit: sensor.fahrenheit? ? "F" : "C") ])
    end

    # A whole outdoor window, already Celsius and already timestamped. Re-sent in
    # full every poll — that is how a gap self-heals — so this must upsert, and
    # one bad row must not cost the rest of the batch.
    def self.upsert_series!(sensor:, rows:)
      now = Time.current

      records = Array(rows).filter_map do |row|
        # forecast_days is requested for self-heal margin only; storing the
        # forecast tail would draw predictions as if they were observations.
        next if row[:recorded_at].nil? || row[:recorded_at] > now

        begin
          validate!(sensor, row[:temperature_c], row[:relative_humidity])
        rescue ImplausibleReading => e
          Rails.logger.warn("[climate] skipping implausible outdoor row: #{e.message}")
          next
        end

        row_for(sensor: sensor, recorded_at: row[:recorded_at],
                temperature_c: row[:temperature_c], relative_humidity: row[:relative_humidity],
                dew_point_c: row[:dew_point_c], raw_temperature: row[:temperature_c],
                raw_temperature_unit: "C")
      end

      write(records)
    end

    def self.to_celsius(raw, sensor)
      return nil if raw.nil?

      sensor.fahrenheit? ? ((raw.to_f - 32.0) * 5.0 / 9.0).round(2) : raw.to_f.round(2)
    end
    private_class_method :to_celsius

    def self.validate!(sensor, celsius, humidity)
      if celsius.nil? || !PLAUSIBLE_CELSIUS.cover?(celsius)
        raise ImplausibleReading,
              "#{sensor.display_name}: temperature #{celsius.inspect} °C outside #{PLAUSIBLE_CELSIUS}"
      end

      return if humidity.present? && PLAUSIBLE_HUMIDITY.cover?(humidity.to_f)

      raise ImplausibleReading,
            "#{sensor.display_name}: humidity #{humidity.inspect} % outside #{PLAUSIBLE_HUMIDITY}"
    end
    private_class_method :validate!

    def self.row_for(sensor:, recorded_at:, temperature_c:, relative_humidity:, dew_point_c:,
                     raw_temperature:, raw_temperature_unit:)
      now = Time.current
      { sensor_id: sensor.id, recorded_at: recorded_at,
        temperature_c: temperature_c, relative_humidity: relative_humidity,
        dew_point_c: dew_point_c,
        raw_temperature: raw_temperature, raw_temperature_unit: raw_temperature_unit,
        created_at: now, updated_at: now }
    end
    private_class_method :row_for

    # MySQL ignores upsert_all's unique_by: — it collides on whatever unique
    # index the row hits, so that index must exist before the first poll.
    def self.write(records)
      return 0 if records.empty?

      Reading.upsert_all(records,
                         update_only: %i[temperature_c relative_humidity dew_point_c
                                         raw_temperature raw_temperature_unit updated_at])
      records.size
    end
    private_class_method :write
  end
end
