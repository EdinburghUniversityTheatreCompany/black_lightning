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
end
