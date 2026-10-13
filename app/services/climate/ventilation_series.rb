module Climate
  ##
  # "Should I open the doors?": the crypt's temperature and dew point against
  # the outside dew point, all in °C on one axis.
  #
  # Outside dew point ABOVE the crypt's temperature means incoming air condenses
  # on the stone however dry it feels. BELOW the crypt's dew point it is drier in
  # absolute terms, so opening up dries the place out. Relative humidity cannot
  # be compared across different temperatures; dew point can.
  #
  # A projection over SeriesQuery, not new SQL, so the aggregate is AVG
  # deliberately: this chart is read for the present, and MarginSeries owns the
  # historical worst case.
  class VentilationSeries
    WORST = "worst".freeze
    NOT_IN_CRYPT = "That sensor is not marked as being in the crypt, so the coldest one is shown instead.".freeze

    def initialize(crypt_sensors:, outdoor_sensor:, range:, selected: nil)
      @crypt_sensors = Array(crypt_sensors)
      @outdoor_sensor = outdoor_sensor
      @range = range
      @selected = selected.presence
    end

    def options
      [ [ "Coldest crypt sensor", WORST ] ] +
        @crypt_sensors.map { |sensor| [ sensor.display_name, sensor.id.to_s ] }
    end

    def sensor = resolved[:sensor]
    def notice = resolved[:notice]

    # WORST is reported back as WORST, not as the sensor it resolved to, so the
    # selection keeps meaning "coldest" as the range changes.
    def selected_key = resolved[:key]

    # -> [{ key:, label:, style:, color_index:, points: [{ t:, value: }] }]
    def series = @series ||= build_series

    private

    def build_series
      return [] if sensor.nil?

      raw = SeriesQuery.new(sensors: [ sensor, @outdoor_sensor ].compact, range: @range).series
      crypt = raw.find { |line| line[:id] == sensor.id }
      outdoor = @outdoor_sensor && raw.find { |line| line[:id] == @outdoor_sensor.id }

      [
        line("crypt_temperature", "#{sensor.display_name} temperature", crypt, :temperature, "solid"),
        line("crypt_dew_point", "#{sensor.display_name} dew point", crypt, :dew_point, "muted"),
        outdoor && line("outdoor_dew_point", "Outside dew point", outdoor, :dew_point, "dashed")
      ].compact
    end

    def line(key, label, source, measure, style)
      { key: key, label: label, style: style, color_index: source[:color_index],
        points: source[:points].map { |point| { t: point[:t], value: point[measure] } } }
    end

    def resolved
      @resolved ||= resolve
    end

    def resolve
      return { sensor: nil, notice: nil, key: WORST } if @crypt_sensors.empty?
      return { sensor: coldest, notice: nil, key: WORST } if @selected.nil? || @selected == WORST

      chosen = @crypt_sensors.find { |sensor| sensor.id.to_s == @selected }
      return { sensor: chosen, notice: nil, key: chosen.id.to_s } if chosen

      { sensor: coldest, notice: NOT_IN_CRYPT, key: WORST }
    end

    # Condensation happens at the coldest spot. Resolved once from the LOWEST
    # MEAN temperature over the range, so both crypt lines come from the same
    # sensor: the gap between a temperature and a dew point from different
    # sensors could not be read, and that gap is what anyone reads first.
    def coldest
      means = Reading
              .where(sensor_id: @crypt_sensors.map(&:id),
                     recorded_at: @range.starts_at..@range.ends_at)
              .group(:sensor_id)
              .average(:temperature_c)

      @crypt_sensors.min_by { |sensor| means[sensor.id] || Float::INFINITY }
    end
  end
end
