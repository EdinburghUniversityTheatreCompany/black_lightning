module Climate
  ##
  # How wide a chart bucket is for a given span, the SQL that floors a
  # timestamp into one, and where a series has to BREAK rather than be drawn
  # across.
  #
  # Extracted from SeriesQuery so the four chart payloads share one rule: a
  # margin line bucketed differently from the temperature line above it would
  # be unreadable next to it.
  class Buckets
    HOUR = 3_600

    # Bucket width by span. Each keeps a series under about 800 points.
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

    # Capped at a day so a narrow ?from=/?to= that clips a sensor's dense runs
    # to a couple of far-apart points can't read that spacing as its normal
    # cadence and stretch the outage tolerance arbitrarily far. A day is
    # RESOLUTIONS' own widest bucket, not an arbitrary pick. Applied to the
    # CADENCE (see #gap_threshold), not the final threshold, so GAP_BUCKETS
    # still multiplies a bounded number.
    #
    # #max, not RESOLUTIONS.last: #initialize's `find` only works because
    # RESOLUTIONS is ordered by max_days, and this cap must stay the widest
    # bucket even if that ordering ever changes — .last would silently pick a
    # smaller ceiling, and #gap_threshold's clamp would then raise once the
    # max dipped below the min.
    MAX_CADENCE_SECONDS = RESOLUTIONS.map { |r| r[:seconds] }.max

    RAW_SECONDS = RESOLUTIONS.first[:seconds]

    attr_reader :seconds

    def initialize(range)
      @seconds = RESOLUTIONS.find { |r| r[:max_days].nil? || range.days <= r[:max_days] }[:seconds]
    end

    def expression = BUCKET_EXPRESSIONS.fetch(seconds)

    # False when each bucket holds at most one reading, which is when a
    # min-max band would be a zero-width artefact rather than a spread.
    def aggregated? = seconds > RAW_SECONDS

    # DATE() buckets come back as a Date, the DATE_SUB ones as a Time.
    def to_time(bucket)
      bucket.is_a?(Date) && !bucket.is_a?(Time) ? bucket.beginning_of_day.in_time_zone : bucket.in_time_zone
    end

    # An explicit null wherever the series skips, so the chart BREAKS the line
    # rather than interpolating across an outage. A line drawn through missing
    # data is not cosmetic. It is a reading of the room that never happened.
    def with_gaps(points, keys:)
      threshold = gap_threshold(points)
      blank = keys.index_with(nil)

      points.each_with_object([]) do |current, result|
        previous = result.last
        result << blank.merge(t: previous[:t] + seconds) if previous && (current[:t] - previous[:t]) > threshold
        result << current
      end.map { |entry| entry.merge(t: entry[:t].iso8601) }
    end

    private

    # Derived from how THIS series actually reports, not the chart's own
    # bucket width: Open-Meteo reports hourly while the 24-hour chart buckets
    # at ten minutes, so a bucket-width threshold would flag the gap after
    # every single outdoor point as its own outage — pointRadius is 0, so an
    # isolated point disappears too (see the JS side's pointRadiusUnlessIsolated).
    #
    # The estimate is the MINIMUM consecutive delta, but only with two or more
    # to compare: an outage only ever widens a gap, so it can inflate the
    # other deltas but never pull the minimum below the series' true cadence.
    # With fewer than two deltas there's nothing to compare against — a lone
    # 30-hour gap is indistinguishable from "reports every 30 hours," so
    # treating it as the cadence would make the threshold 3x itself and never
    # exceeded. The fallback there is the chart's own bucket width.
    def gap_threshold(points)
      deltas = points.each_cons(2).map { |(a, b)| b[:t] - a[:t] }
      cadence = deltas.size >= 2 ? deltas.min : seconds

      cadence.clamp(seconds, MAX_CADENCE_SECONDS) * GAP_BUCKETS
    end
  end
end
