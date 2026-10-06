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

  test "renders every timestamp as an iso8601 string" do
    subject = buckets(from: "2026-08-05", to: "2026-08-06")
    points = [ { t: Time.zone.parse("2026-08-05 12:00"), margin: 4.0 } ]

    assert_kind_of String, subject.with_gaps(points, keys: [ :margin ]).first[:t]
  end

  # The gap threshold follows each series' own cadence: Open-Meteo is hourly but
  # the 24-hour view buckets at 600s, so a bucket-width threshold would break
  # the line after every outdoor point and draw nothing.

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
