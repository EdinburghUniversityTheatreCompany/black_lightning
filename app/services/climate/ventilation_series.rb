module Climate
  ##
  # "Should I open the doors?" — the crypt's temperature and dew point against
  # the outside air's dew point, all in °C on one axis.
  #
  # Two readings from one chart. Outdoor dew point ABOVE the crypt's
  # temperature means the incoming air condenses on the stone however dry it
  # feels out there. Outdoor dew point BELOW the crypt's dew point means the
  # air is drier in absolute terms, so opening up dries the place out.
  # Relative humidity cannot be compared between two places at different
  # temperatures; dew point can, which is why all three lines are °C.
  #
  # A projection over SeriesQuery rather than new SQL: these are the numbers
  # the history charts already fetch, relabelled onto one axis. So the
  # aggregate is AVG, deliberately — this chart is read for the present, where
  # the buckets are raw anyway, and MarginSeries owns the historical worst case.
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
    # selection keeps meaning "whichever is coldest" as the range changes.
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

    # The coldest spot is where condensation happens. Resolved once from the
    # LOWEST MEAN temperature over the whole range rather than point by point,
    # so both crypt lines come from the same sensor: a chart whose temperature
    # and dew point came from different sensors could not be read for the gap
    # between them, and that gap is the first thing anyone reads.
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
