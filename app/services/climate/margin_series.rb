module Climate
  ##
  # The condensation-risk line: how far the crypt's air sat from its own dew
  # point, and how close that ever came to zero.
  #
  # The aggregate is MIN(temperature_c - dew_point_c) — the margin per row,
  # then the worst of them. NOT MIN(temperature_c) - MAX(dew_point_c), which
  # takes its two figures from different instants and invents a colder, wetter
  # crypt than ever existed. And not AVG: condensation is a worst-case event,
  # so a daily mean can sit comfortably at 5 °C while every night touched 1.
  #
  # Measured against the AIR, not the walls. The walls are underground and
  # colder, so the real margin at the stone is smaller than this line.
  class MarginSeries
    def initialize(sensors:, range:)
      @sensors = Array(sensors)
      @range = range
      @buckets = Buckets.new(range)
      @colors = SeriesColors.new
    end

    def bucket_seconds = @buckets.seconds

    # -> [{ id:, name:, color_index:, points: [{ t: iso8601, margin: }] }]
    def series
      grouped = bucketed_rows

      @sensors.map do |sensor|
        { id: sensor.id, name: sensor.display_name,
          color_index: @colors.index_for(sensor),
          points: @buckets.with_gaps(grouped.fetch(sensor.id, []), keys: [ :margin ]) }
      end
    end

    private

    # Written as a literal Arel.sql call, not built by interpolating a
    # constant: Brakeman flags an interpolated Arel.sql argument as a
    # possible SQL injection even when, as here, it can only ever come from a
    # frozen constant. See Climate::SeriesQuery#aggregates for the same rule.
    def bucketed_rows
      return {} if @sensors.empty?

      expression = @buckets.expression

      rows = Reading
             .where(sensor_id: @sensors.map(&:id), recorded_at: @range.starts_at..@range.ends_at)
             .where.not(temperature_c: nil).where.not(dew_point_c: nil)
             .group(:sensor_id, Arel.sql(expression))
             .order(Arel.sql("1 ASC, 2 ASC"))
             .pluck(:sensor_id, Arel.sql(expression), Arel.sql("MIN(temperature_c - dew_point_c)"))

      rows.group_by(&:first).transform_values do |sensor_rows|
        sensor_rows.map do |(_sensor_id, bucket, margin)|
          { t: @buckets.to_time(bucket), margin: margin&.to_f&.round(2) }
        end
      end
    end
  end
end
