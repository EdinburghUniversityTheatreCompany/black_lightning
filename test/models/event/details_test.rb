require "test_helper"

##
# Running time, doors, and age guidance: three things that were only ever written
# in prose inside publicity_text, where nothing could read them.
##
class Event::DetailsTest < ActiveSupport::TestCase
  setup do
    @show = FactoryBot.create(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7))
  end

  test "a running time must be a positive number of minutes" do
    [ 0, -30 ].each do |minutes|
      @show.duration_minutes = minutes

      assert_not @show.valid?, "#{minutes} minutes should be rejected"
      assert @show.errors[:duration_minutes].present?
    end
  end

  # A fat-finger backstop. Nothing at Bedlam runs for a day.
  test "a running time longer than a day is rejected" do
    @show.duration_minutes = 1500

    assert_not @show.valid?
    assert @show.errors[:duration_minutes].present?
  end

  test "a blank running time is fine" do
    @show.duration_minutes = nil

    assert_predicate @show, :valid?
  end

  test "doors cannot open after the curtain" do
    @show.doors_open_minutes_before = -10

    assert_not @show.valid?
    assert @show.errors[:doors_open_minutes_before].present?
  end

  # A decimal column casts "abc" to 0 without complaint, and £0 was then published
  # as "£0 booking fee on the door".
  test "an unreadable booking fee is rejected rather than cast to zero" do
    @show.booking_fee = "abc"

    assert_not @show.valid?
    assert @show.errors[:booking_fee].present?
  end

  test "a real booking fee is accepted" do
    @show.booking_fee = "1.50"

    assert_predicate @show, :valid?
  end

  # --- what the running time buys ---------------------------------------

  test "an occurrence with no end time takes one from the running time" do
    @show.update!(duration_minutes: 135)
    occurrence = EventOccurrence.create!(event: @show, starts_at: Time.zone.local(2026, 3, 4, 19, 30))

    assert_equal Time.zone.local(2026, 3, 4, 21, 45), occurrence.effective_ends_at
  end

  test "an explicit end time wins over the running time" do
    @show.update!(duration_minutes: 135)
    occurrence = EventOccurrence.create!(event: @show, starts_at: Time.zone.local(2026, 3, 4, 19, 30),
                                                       ends_at: Time.zone.local(2026, 3, 4, 22, 30))

    assert_equal Time.zone.local(2026, 3, 4, 22, 30), occurrence.effective_ends_at
  end

  test "with neither, an occurrence has no end time to give" do
    occurrence = EventOccurrence.create!(event: @show, starts_at: Time.zone.local(2026, 3, 4, 19, 30))

    assert_nil occurrence.effective_ends_at
  end

  test "doors open the stated number of minutes before the curtain" do
    @show.update!(doors_open_minutes_before: 30)
    occurrence = EventOccurrence.create!(event: @show, starts_at: Time.zone.local(2026, 3, 4, 19, 30))

    assert_equal Time.zone.local(2026, 3, 4, 19, 0), occurrence.doors_open_at
  end

  test "without a doors setting there is no door time to state" do
    occurrence = EventOccurrence.create!(event: @show, starts_at: Time.zone.local(2026, 3, 4, 19, 30))

    assert_nil occurrence.doors_open_at
  end

  # --- ISO 8601, which is what schema.org wants --------------------------

  test "the running time renders as an ISO 8601 duration" do
    { 135 => "PT2H15M", 60 => "PT1H", 45 => "PT45M", 120 => "PT2H" }.each do |minutes, expected|
      @show.duration_minutes = minutes

      assert_equal expected, @show.iso8601_duration, "#{minutes} minutes"
    end
  end

  test "no running time means no duration to state" do
    @show.duration_minutes = nil

    assert_nil @show.iso8601_duration
  end
end
