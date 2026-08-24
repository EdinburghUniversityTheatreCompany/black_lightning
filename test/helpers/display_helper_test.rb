require "test_helper"

class DisplayHelperTest < ActionView::TestCase
  include DisplayHelper

  test "display_date_range collapses a single day" do
    event = FactoryBot.build(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 3))

    assert_equal "Tue 3 Mar", display_date_range(event)
  end

  test "display_date_range drops the repeated month" do
    event = FactoryBot.build(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7))

    assert_equal "Tue 3 – Sat 7 Mar", display_date_range(event)
  end

  test "display_date_range keeps both months when the run crosses one" do
    event = FactoryBot.build(:show, start_date: Date.new(2026, 3, 30), end_date: Date.new(2026, 4, 2))

    assert_equal "Mon 30 Mar – Thu 2 Apr", display_date_range(event)
  end

  test "display_when says the weekday for a run that plays one day a week" do
    # A year-long range tells nobody when to turn up; "Every Friday" does.
    event = FactoryBot.build(:show, start_date: Date.new(2026, 9, 1), end_date: Date.new(2027, 6, 30),
                                    performance_weekdays: "5")

    assert_equal "Every Friday", display_when(event)
  end

  test "display_when falls back to the range when no performance days are set" do
    event = FactoryBot.build(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7))

    assert_equal "Tue 3 – Sat 7 Mar", display_when(event)
  end
end
