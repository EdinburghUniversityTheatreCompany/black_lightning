module Climate
  ##
  # The single write path into climate_readings: the plausibility guard, the dew
  # point and the idempotent upsert. Nothing else should create a
  # Climate::Reading.
  #
  # Both feeds arrive as a whole window of already-timestamped rows — a CSV
  # export for the crypt sensors, an hourly forecast window for outdoors — so
  # there is one method, and re-sending an overlapping window is the normal case
  # rather than an error.
  class ReadingIngest
    # An Edinburgh basement reaches neither bound, so anything outside is a
    # mis-read column or a broken sensor rather than weather.
    PLAUSIBLE_CELSIUS = (-20.0..50.0)
    PLAUSIBLE_HUMIDITY = (0.0..100.0)

    class Error < StandardError; end
    class ImplausibleReading < Error; end

    Result = Struct.new(:written, :skipped, :future, :range, keyword_init: true) do
      def total = written + skipped + future
    end

    # +rows+: [{ recorded_at:, temperature_c:, relative_humidity:, dew_point_c:,
    #            raw_temperature:, raw_temperature_unit: }]
    # dew_point_c and the raw pair are optional — dew point is computed when
    # absent, and the raw pair defaults to the Celsius value.
    #
    # One bad row is skipped rather than failing the batch: a single unreadable
    # line in a 2,000-row export must not cost the other 1,999.
    def self.upsert_series!(sensor:, rows:)
      now = Time.current
      skipped = 0
      future = 0
      stamps = []

      records = Array(rows).filter_map do |row|
        recorded_at = row[:recorded_at]
        # Bare `next`, never `next(counter += 1)` — that returns the assignment's
        # Integer, which filter_map then keeps as though it were a record.
        if recorded_at.nil?
          skipped += 1
          next
        end

        # A forecast window is fetched for self-heal margin only, and a CSV
        # should never contain the future; storing either would draw a
        # prediction as though it were a measurement.
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
        # What the source actually said, before any conversion — so a column
        # misread as the wrong unit stays correctable from the stored value.
        raw_temperature: row[:raw_temperature] || celsius,
        raw_temperature_unit: row[:raw_temperature_unit] || "C",
        created_at: now, updated_at: now }
    end
    private_class_method :row_for

    # MySQL ignores upsert_all's unique_by: — it collides on whatever unique
    # index the row hits, so that index must exist before the first import.
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
