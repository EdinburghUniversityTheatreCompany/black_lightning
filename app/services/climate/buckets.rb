module Climate
  ##
  # Bucket width for a span, the SQL that floors a timestamp into one, and where
  # a series has to BREAK rather than be drawn across. Shared, so every chart
  # payload buckets alike.
  class Buckets
    HOUR = 3_600

    # Bucket width by span. Each keeps a series under about 800 points.
    RESOLUTIONS = [
      { max_days: 2,   seconds: 600 },     # raw
      { max_days: 14,  seconds: HOUR },
      { max_days: 90,  seconds: 6 * HOUR },
      { max_days: nil, seconds: 24 * HOUR }
    ].freeze

    # A frozen allow-list, so nothing user-supplied reaches the SQL string.
    #
    # NOT FROM_UNIXTIME(FLOOR(UNIX_TIMESTAMP(recorded_at)/n)*n): mysql2 does not
    # pin the session time_zone, so UNIX_TIMESTAMP() reads the stored UTC value
    # in the SERVER's zone and shifts every bucket boundary by its offset.
    BUCKET_EXPRESSIONS = {
      600 => "DATE_SUB(recorded_at, INTERVAL (TIME_TO_SEC(TIME(recorded_at)) % 600) SECOND)",
      3_600 => "DATE_SUB(recorded_at, INTERVAL (TIME_TO_SEC(TIME(recorded_at)) % 3600) SECOND)",
      21_600 => "DATE_SUB(recorded_at, INTERVAL (TIME_TO_SEC(TIME(recorded_at)) % 21600) SECOND)",
      86_400 => "DATE(recorded_at)"
    }.freeze

    # A break longer than this many buckets is drawn as a gap rather than a line.
    GAP_BUCKETS = 3

    # The cadence is capped at the widest bucket (a day), so a narrow
    # ?from=/?to= that clips a sensor to a couple of far-apart points cannot
    # read that spacing as its normal cadence and stretch the outage tolerance
    # without limit. #max, not .last, so it survives a reordering of RESOLUTIONS.
    MAX_CADENCE_SECONDS = RESOLUTIONS.map { |r| r[:seconds] }.max

    RAW_SECONDS = RESOLUTIONS.first[:seconds]

    attr_reader :seconds

    def initialize(range, seconds: nil)
      @seconds = seconds || RESOLUTIONS.find { |r| r[:max_days].nil? || range.days <= r[:max_days] }[:seconds]
    end

    def expression = BUCKET_EXPRESSIONS.fetch(seconds)

    # False at raw resolution, where a min-max band would be a zero-width artefact.
    def aggregated? = seconds > RAW_SECONDS

    # An explicit null wherever the series skips, so the chart BREAKS the line
    # instead of interpolating: a line through missing data is a reading that
    # never happened.
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

    # Derived from how THIS series reports, not the chart's bucket width:
    # Open-Meteo is hourly while the 24-hour view buckets at 600s, so a
    # bucket-width threshold would break the line after every outdoor point.
    #
    # The cadence is the MINIMUM delta, but only with two or more to compare (an
    # outage widens gaps, it never pulls the minimum below the true cadence).
    # With fewer, a lone 30-hour gap reads as "reports every 30 hours" and could
    # never exceed 3x itself, so the fallback is the bucket width.
    def gap_threshold(points)
      deltas = points.each_cons(2).map { |(a, b)| b[:t] - a[:t] }
      cadence = deltas.size >= 2 ? deltas.min : seconds

      cadence.clamp(seconds, MAX_CADENCE_SECONDS) * GAP_BUCKETS
    end
  end
end
