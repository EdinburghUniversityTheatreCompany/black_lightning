module Climate
  ##
  # The chart payload: one series per sensor, bucketed to suit the span.
  class SeriesQuery
    MEASURES = { temperature: "temperature_c", humidity: "relative_humidity",
                 dew_point: "dew_point_c" }.freeze

    POINT_KEYS = MEASURES.keys.flat_map { |m| [ m, :"#{m}_min", :"#{m}_max" ] }.freeze

    def initialize(sensors:, range:)
      @sensors = Array(sensors)
      @range = range
      @buckets = Buckets.new(range)
      @colors = SeriesColors.new
    end

    def aggregated? = @buckets.aggregated?

    # -> [{ id:, name:, location:, placement:, outdoor:, color_index:,
    #       points: [{ t: iso8601, temperature:, temperature_min:,
    #                  temperature_max:, humidity:, …, dew_point:, … }] }]
    def series
      grouped = bucketed_rows

      @sensors.map do |sensor|
        { id: sensor.id, name: sensor.display_name, location: sensor.location,
          placement: sensor.placement, outdoor: sensor.outdoor?,
          color_index: @colors.index_for(sensor),
          points: @buckets.with_gaps(grouped.fetch(sensor.id, []), keys: POINT_KEYS) }
      end
    end

    private

    # AVG for the line, MIN/MAX for the band: once a bucket is wider than one
    # reading the mean hides the extremes, and the extreme is what condenses.
    #
    # Literal Arel.sql calls: Brakeman flags interpolation into Arel.sql as a
    # possible injection even from a frozen constant.
    def aggregates
      [ Arel.sql("AVG(temperature_c)"), Arel.sql("MIN(temperature_c)"), Arel.sql("MAX(temperature_c)"),
        Arel.sql("AVG(relative_humidity)"), Arel.sql("MIN(relative_humidity)"), Arel.sql("MAX(relative_humidity)"),
        Arel.sql("AVG(dew_point_c)"), Arel.sql("MIN(dew_point_c)"), Arel.sql("MAX(dew_point_c)") ]
    end

    def bucketed_rows
      return {} if @sensors.empty?

      expression = @buckets.expression

      rows = Reading
             .where(sensor_id: @sensors.map(&:id), recorded_at: @range.starts_at..@range.ends_at)
             .group(:sensor_id, Arel.sql(expression))
             .order(Arel.sql("1 ASC, 2 ASC"))
             .pluck(:sensor_id, Arel.sql(expression), *aggregates)

      rows.group_by(&:first).transform_values { |sensor_rows| sensor_rows.map { |row| point(row) } }
    end

    def point(row)
      _sensor_id, bucket, *values = row

      MEASURES.keys.each_with_index.each_with_object({ t: bucket.in_time_zone }) do |(measure, index), result|
        mean, minimum, maximum = values[index * 3, 3]
        result[measure] = round(mean)
        result[:"#{measure}_min"] = round(minimum)
        result[:"#{measure}_max"] = round(maximum)
      end
    end

    def round(value) = value&.to_f&.round(2)
  end
end
