module Climate
  ##
  # The single write path into climate_readings: plausibility guard, dew point
  # and idempotent upsert. Both feeds send whole windows of timestamped rows, so
  # re-sending an overlap is the normal case.
  class ReadingIngest
    # Anything outside is a mis-read column or a broken sensor, not weather.
    PLAUSIBLE_CELSIUS = (-20.0..50.0)
    PLAUSIBLE_HUMIDITY = (0.0..100.0)

    class Error < StandardError; end
    class ImplausibleReading < Error; end

    Result = Struct.new(:written, :skipped, :future, :range, keyword_init: true) do
      def total = written + skipped + future
    end

    # +rows+: [{ recorded_at:, temperature_c:, relative_humidity:, dew_point_c:,
    #            raw_temperature:, raw_temperature_unit: }]
    # dew_point_c and the raw pair are optional: the dew point is computed when
    # absent, the raw pair defaults to the Celsius value. One bad row is skipped
    # rather than failing the batch.
    def self.upsert_series!(sensor:, rows:)
      now = Time.current
      skipped = 0
      future = 0
      stamps = []

      records = Array(rows).filter_map do |row|
        recorded_at = row[:recorded_at]
        # Bare `next`, never `next(counter += 1)`: filter_map would keep the
        # Integer as a record.
        if recorded_at.nil?
          skipped += 1
          next
        end

        # Dropped so a forecast is never drawn as a measurement.
        if recorded_at > now
          future += 1
          next
        end

        begin
          validate!(sensor, row[:temperature_c], row[:relative_humidity])
        rescue ImplausibleReading => e
          Rails.logger.warn("[climate] skipping implausible row: #{e.message}")
          skipped += 1
          next
        end

        stamps << recorded_at
        row_for(sensor: sensor, row: row)
      end

      Result.new(written: write(records), skipped: skipped, future: future,
                 range: (stamps.min..stamps.max if stamps.any?))
    end

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

    def self.row_for(sensor:, row:)
      now = Time.current
      celsius = row[:temperature_c]
      humidity = row[:relative_humidity]

      { sensor_id: sensor.id, recorded_at: row[:recorded_at],
        temperature_c: celsius, relative_humidity: humidity,
        dew_point_c: row[:dew_point_c] ||
          DewPoint.celsius(temperature_c: celsius, relative_humidity: humidity),
        # What the source said, before conversion, so a column misread as the
        # wrong unit stays correctable.
        raw_temperature: row[:raw_temperature] || celsius,
        raw_temperature_unit: row[:raw_temperature_unit] || "C",
        created_at: now, updated_at: now }
    end
    private_class_method :row_for

    # MySQL ignores upsert_all's unique_by: and collides on whatever unique index
    # the row hits, so that index must exist before the first import.
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
