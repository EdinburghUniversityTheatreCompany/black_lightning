require "test_helper"

class Climate::BucketsTest < ActiveSupport::TestCase
  def buckets(from:, to:)
    Climate::Buckets.new(Climate::DateRange.from_params({ from: from, to: to }))
  end

  test "keeps raw ten-minute buckets over a short span" do
    assert_equal 600, buckets(from: "2026-08-05", to: "2026-08-06").seconds
  end

  test "buckets hourly over a fortnight" do
    assert_equal 3_600, buckets(from: "2026-07-25", to: "2026-08-06").seconds
  end

  test "buckets six-hourly over a quarter" do
    assert_equal 21_600, buckets(from: "2026-06-01", to: "2026-08-06").seconds
  end

  test "buckets daily over a year" do
    assert_equal 86_400, buckets(from: "2025-08-06", to: "2026-08-06").seconds
  end

  test "raw resolution is not aggregated, wider ones are" do
    assert_not_predicate buckets(from: "2026-08-05", to: "2026-08-06"), :aggregated?
    assert_predicate buckets(from: "2026-07-25", to: "2026-08-06"), :aggregated?
  end

  # The mysql2 adapter does not pin the session time_zone, so a UNIX_TIMESTAMP
  # bucket would read the stored value in the SERVER's zone and shift every
  # boundary by its offset. This is the guard against someone "simplifying" it.
  test "every bucket expression is timezone-independent arithmetic" do
    Climate::Buckets::BUCKET_EXPRESSIONS.each_value do |expression|
      assert_no_match(/UNIX_TIMESTAMP/i, expression)
    end
  end

  test "inserts an explicit null point across a gap so the line breaks" do
    subject = buckets(from: "2026-07-25", to: "2026-08-06")
    points = [
      { t: Time.zone.parse("2026-08-05 12:00"), margin: 4.0 },
      { t: Time.zone.parse("2026-08-05 20:00"), margin: 5.0 }
    ]

    result = subject.with_gaps(points, keys: [ :margin ])

    assert_equal 3, result.size
    assert_nil result[1][:margin]
    assert_equal Time.zone.parse("2026-08-05 13:00").iso8601, result[1][:t]
  end

  # With only one delta to compare it has nothing else, so the estimate falls
  # back to the chart's own bucket width rather than the lone observed gap —
  # otherwise the gap and the "cadence" derived from it would be the same
  # number and a real outage could never exceed its own threshold. This is
  # the fallback the test above exercises implicitly; this one states it on
  # its own terms, with a gap that a (deliberately wrong) single-delta
  # estimate would let through.
  test "with only two points, falls back to the bucket width rather than treating the lone gap as the cadence" do
    subject = buckets(from: "2026-08-05", to: "2026-08-06") # 600s bucket
    points = [
      { t: Time.zone.parse("2026-08-05 10:00"), margin: 1.0 },
      # 5h33m later. A single-delta-as-cadence estimate would take this very
      # gap as "normal," multiply it by GAP_BUCKETS, and never break — the
      # bug this fallback exists to prevent.
      { t: Time.zone.parse("2026-08-05 15:33"), margin: 2.0 }
    ]

    result = subject.with_gaps(points, keys: [ :margin ])

    assert_equal 3, result.size
    assert_nil result[1][:margin]
  end

  test "leaves a contiguous run alone" do
    subject = buckets(from: "2026-07-25", to: "2026-08-06")
    points = [
      { t: Time.zone.parse("2026-08-05 12:00"), margin: 4.0 },
      { t: Time.zone.parse("2026-08-05 13:00"), margin: 5.0 }
    ]

    assert_equal 2, subject.with_gaps(points, keys: [ :margin ]).size
  end

  test "renders every timestamp as an iso8601 string" do
    subject = buckets(from: "2026-08-05", to: "2026-08-06")
    points = [ { t: Time.zone.parse("2026-08-05 12:00"), margin: 4.0 } ]

    assert_kind_of String, subject.with_gaps(points, keys: [ :margin ]).first[:t]
  end

  # --- gap threshold is per-series, not per-bucket ----------------------------
  #
  # Open-Meteo reports hourly. On the 24-hour view the chart buckets at ten
  # minutes (600s), so a threshold built from the bucket width alone
  # (600 * GAP_BUCKETS = 1800s) is narrower than the outdoor series' own
  # 3600s cadence: every single outdoor point would be more than a threshold
  # apart from its neighbour, and get an explicit gap inserted after it. With
  # spanGaps: false and pointRadius: 0 that draws nothing at all — the bug.

  test "keeps an hourly series unbroken over a one-day span" do
    subject = buckets(from: "2026-08-05", to: "2026-08-06") # 600s chart bucket
    points = (0..23).map { |hour| { t: Time.zone.parse("2026-08-05 00:00") + hour.hours, margin: 1.0 } }

    result = subject.with_gaps(points, keys: [ :margin ])

    assert_equal 24, result.size
    assert(result.none? { |entry| entry[:margin].nil? })
  end

  test "still breaks an hourly series across a genuine multi-hour hole" do
    subject = buckets(from: "2026-08-05", to: "2026-08-06")
    points = [ 0, 1, 2, 9, 10, 11 ].map { |hour| { t: Time.zone.parse("2026-08-05 00:00") + hour.hours, margin: 1.0 } }

    result = subject.with_gaps(points, keys: [ :margin ])

    assert_includes result.map { |entry| entry[:margin] }, nil
  end

  test "leaves a ten-minutely series over a one-day span unbroken" do
    subject = buckets(from: "2026-08-05", to: "2026-08-06")
    points = (0..143).map { |i| { t: Time.zone.parse("2026-08-05 00:00") + (i * 10).minutes, margin: 1.0 } }

    result = subject.with_gaps(points, keys: [ :margin ])

    assert_equal 144, result.size
    assert(result.none? { |entry| entry[:margin].nil? })
  end

  test "still breaks a ten-minutely series across a genuine hole" do
    subject = buckets(from: "2026-08-05", to: "2026-08-06")
    points = [ 0, 10, 20, 260, 270, 280 ].map { |min| { t: Time.zone.parse("2026-08-05 00:00") + min.minutes, margin: 1.0 } }

    result = subject.with_gaps(points, keys: [ :margin ])

    assert_includes result.map { |entry| entry[:margin] }, nil
  end

  # --- the cadence estimate is capped, so a uniformly sparse view can't earn
  # an unbounded outage tolerance --------------------------------------------
  #
  # A narrow ?from=/?to= can clip a hand-synced sensor's dense runs down to a
  # couple of points ten-plus days apart, with nothing inside the window to
  # contradict that spacing. Without a ceiling, that spacing itself becomes
  # the "cadence," and the threshold (cadence * GAP_BUCKETS) grows just as
  # unbounded — a real month-long outage would render as an unbroken line,
  # the same failure mode the two-point fallback above exists to prevent, just
  # reachable with three or more points instead of two.

  test "caps the estimated cadence at a day, so a uniformly sparse series still breaks across a long outage" do
    subject = buckets(from: "2026-06-01", to: "2026-08-06") # 21_600s (6-hourly) bucket
    points = [
      { t: Time.zone.parse("2026-06-05 00:00"), margin: 1.0 },
      # Ten days later: the only evidence of "normal" spacing in this window.
      # Uncapped, this becomes the cadence, and 25 days would then sit well
      # inside cadence * GAP_BUCKETS (30 days) and never break.
      { t: Time.zone.parse("2026-06-15 00:00"), margin: 2.0 },
      { t: Time.zone.parse("2026-07-10 00:00"), margin: 3.0 }
    ]

    result = subject.with_gaps(points, keys: [ :margin ])

    assert_includes result.map { |entry| entry[:margin] }, nil
  end

  test "does not cap the cadence below the chart's own bucket width" do
    # At the widest (yearly) tier the bucket width already equals the cap
    # (both are a day), so clamping must never push the cadence BELOW
    # seconds — it would fight the floor applied for the 0-or-1-delta case.
    subject = buckets(from: "2025-08-06", to: "2026-08-06") # 86_400s (daily) bucket
    points = [
      { t: Time.zone.parse("2026-08-01"), margin: 1.0 },
      { t: Time.zone.parse("2026-08-02"), margin: 2.0 },
      { t: Time.zone.parse("2026-08-06"), margin: 3.0 }
    ]

    result = subject.with_gaps(points, keys: [ :margin ])

    # cadence = 1 day, threshold = 3 days: the 4-day gap (08-02 -> 08-06) breaks.
    assert_includes result.map { |entry| entry[:margin] }, nil
  end
end
