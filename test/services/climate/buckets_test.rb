require "test_helper"

class Climate::BucketsTest < ActiveSupport::TestCase
  def buckets(from:, to:)
    Climate::Buckets.new(Climate::DateRange.from_params({ from: from, to: to }))
  end

  test "picks the bucket width for the span, aggregating past raw" do
    { "2026-08-05" => [ 600, false ], "2026-07-25" => [ 3_600, true ],
      "2026-06-01" => [ 21_600, true ], "2025-08-06" => [ 86_400, true ] }.each do |from, (seconds, aggregated)|
      subject = buckets(from: from, to: "2026-08-06")

      assert_equal seconds, subject.seconds, from
      assert_equal aggregated, subject.aggregated?, from
    end
  end

  # Guards against "simplifying" to UNIX_TIMESTAMP, which mysql2's unpinned
  # session time_zone makes shift every boundary by the server's offset.
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

  # A lone delta as the cadence would make a real outage never exceed its own threshold.
  test "with only two points, falls back to the bucket width rather than treating the lone gap as the cadence" do
    subject = buckets(from: "2026-08-05", to: "2026-08-06") # 600s bucket
    points = [
      { t: Time.zone.parse("2026-08-05 10:00"), margin: 1.0 },
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

  # The gap threshold follows each series' own cadence: Open-Meteo is hourly but
  # the 24-hour view buckets at 600s, so a bucket-width threshold would break
  # the line after every outdoor point and draw nothing.
  test "breaks a series only across a hole wider than its own cadence" do
    subject = buckets(from: "2026-08-05", to: "2026-08-06") # 600s chart bucket
    start = Time.zone.parse("2026-08-05 00:00")
    cases = {
      "hourly, unbroken" => [ (0..23).map(&:hours), false ],
      "hourly, multi-hour hole" => [ [ 0, 1, 2, 9, 10, 11 ].map(&:hours), true ],
      "ten-minutely, unbroken" => [ (0..143).map { |i| (i * 10).minutes }, false ],
      "ten-minutely, hole" => [ [ 0, 10, 20, 260, 270, 280 ].map(&:minutes), true ]
    }

    cases.each do |name, (offsets, breaks)|
      points = offsets.map { |offset| { t: start + offset, margin: 1.0 } }

      assert_equal breaks, subject.with_gaps(points, keys: [ :margin ]).pluck(:margin).include?(nil), name
    end
  end

  # A narrow range can clip a sensor to points ten-plus days apart. Uncapped, that
  # spacing becomes the cadence and a month-long outage draws as a line.
  test "caps the estimated cadence at a day, so a uniformly sparse series still breaks across a long outage" do
    subject = buckets(from: "2026-06-01", to: "2026-08-06") # 21_600s (6-hourly) bucket
    points = [
      { t: Time.zone.parse("2026-06-05 00:00"), margin: 1.0 },
      # Uncapped, these ten days become the cadence, so 25 days sits inside 3x.
      { t: Time.zone.parse("2026-06-15 00:00"), margin: 2.0 },
      { t: Time.zone.parse("2026-07-10 00:00"), margin: 3.0 }
    ]

    result = subject.with_gaps(points, keys: [ :margin ])

    assert_includes result.map { |entry| entry[:margin] }, nil
  end

  test "does not cap the cadence below the chart's own bucket width" do
    # At the daily tier the bucket width equals the cap, so the clamp must
    # never push the cadence below the bucket width.
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
