module Climate
  ##
  # Turns stored readings into the chart payload: one series per sensor, each a
  # list of points bucketed to a resolution that suits the requested span.
  #
  # A year of ten-minute readings is 52,560 points per sensor. Bucketing takes
  # that to 365, which is what keeps the page a fixed ~25 KB regardless of range
  # and is why the payload can be embedded in the HTML rather than fetched.
  class SeriesQuery
    # Bucket width by span. Each keeps a series under about 800 points.
    HOUR = 3_600
    RESOLUTIONS = [
      { max_days: 2,   seconds: 600 },     # raw
      { max_days: 14,  seconds: HOUR },
      { max_days: 90,  seconds: 6 * HOUR },
      { max_days: nil, seconds: 24 * HOUR }
    ].freeze

    # A frozen allow-list, so nothing user-supplied can reach the SQL string.
    #
    # NOT FROM_UNIXTIME(FLOOR(UNIX_TIMESTAMP(recorded_at)/n)*n): the mysql2
    # adapter stores UTC but does not pin the session time_zone, so
    # UNIX_TIMESTAMP() reads the stored value in the SERVER's zone and every
    # bucket boundary silently shifts by its offset. The arithmetic below is
    # timezone-independent for any bucket that divides a day.
    BUCKET_EXPRESSIONS = {
      600 => "DATE_SUB(recorded_at, INTERVAL (TIME_TO_SEC(TIME(recorded_at)) % 600) SECOND)",
      3_600 => "DATE_SUB(recorded_at, INTERVAL (TIME_TO_SEC(TIME(recorded_at)) % 3600) SECOND)",
      21_600 => "DATE_SUB(recorded_at, INTERVAL (TIME_TO_SEC(TIME(recorded_at)) % 21600) SECOND)",
      86_400 => "DATE(recorded_at)"
    }.freeze

    # A break longer than this many buckets is drawn as a gap rather than a line.
    GAP_BUCKETS = 3

    def initialize(sensors:, range:)
      @sensors = Array(sensors)
      @range = range
    end

    def bucket_seconds
      @bucket_seconds ||= RESOLUTIONS.find { |r| r[:max_days].nil? || @range.days <= r[:max_days] }[:seconds]
    end

    # -> [{ id:, name:, location:, placement:, outdoor:, color_index:,
    #       points: [{ t: iso8601, temperature:, humidity:, dew_point: }] }]
    def series
      grouped = bucketed_rows

      @sensors.map do |sensor|
        { id: sensor.id, name: sensor.display_name, location: sensor.location,
          placement: sensor.placement, outdoor: sensor.outdoor?,
          color_index: color_index(sensor),
          points: with_gaps(grouped.fetch(sensor.id, [])) }
      end
    end

    private

    # Colour follows the SENSOR, not its position in the current selection —
    # deactivating one sensor must not repaint the others. Ranking by id across
    # every sensor (not just the ones on screen) is stable under exactly the
    # operation that filters this list.
    def color_index(sensor)
      @all_ids ||= Sensor.order(:id).pluck(:id)
      @all_ids.index(sensor.id) || 0
    end

    def bucketed_rows
      return {} if @sensors.empty?

      expression = BUCKET_EXPRESSIONS.fetch(bucket_seconds)

      rows = Reading
             .where(sensor_id: @sensors.map(&:id), recorded_at: @range.starts_at..@range.ends_at)
             .group(:sensor_id, Arel.sql(expression))
             .order(Arel.sql("1 ASC, 2 ASC"))
             .pluck(:sensor_id, Arel.sql(expression),
                    Arel.sql("AVG(temperature_c)"), Arel.sql("AVG(relative_humidity)"),
                    Arel.sql("AVG(dew_point_c)"))

      rows.group_by(&:first).transform_values { |sensor_rows| sensor_rows.map { |row| point(row) } }
    end

    def point(row)
      _sensor_id, bucket, temperature, humidity, dew_point = row
      { t: to_time(bucket), temperature: round(temperature),
        humidity: round(humidity), dew_point: round(dew_point) }
    end

    # DATE() buckets come back as a Date, the DATE_SUB ones as a Time.
    def to_time(bucket)
      bucket.is_a?(Date) && !bucket.is_a?(Time) ? bucket.beginning_of_day.in_time_zone : bucket.in_time_zone
    end

    def round(value) = value&.to_f&.round(2)

    # Insert an explicit null wherever the series skips more than a few buckets,
    # so the chart BREAKS the line instead of interpolating straight across a
    # two-day sensor outage. On a damp chart a line drawn through missing data is
    # not a cosmetic problem — it is a reading of the room that never happened.
    def with_gaps(points)
      threshold = bucket_seconds * GAP_BUCKETS

      points.each_with_object([]) do |current, result|
        previous = result.last
        if previous && previous[:t] && (current[:t] - previous[:t]) > threshold
          result << { t: previous[:t] + bucket_seconds, temperature: nil, humidity: nil, dew_point: nil }
        end
        result << current
      end.map { |entry| entry.merge(t: entry[:t].iso8601) }
    end
  end
end
