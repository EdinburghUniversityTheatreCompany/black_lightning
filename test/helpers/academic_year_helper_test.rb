require "test_helper"

class AcademicYearHelperTest < ActionView::TestCase
  test "february" do
    travel_to Time.zone.local(2020, 2, 2, 1, 4, 44)
    assert_2019_20_academic_year
    travel_back
  end

  test "july" do
    travel_to Time.zone.local(2020, 7, 2, 1, 4, 44)
    assert_2019_20_academic_year
    travel_back
  end

  test "october" do
    travel_to Time.zone.local(2020, 10, 2, 1, 4, 44)

    assert_equal Date.new(2020, 9, 1), start_of_year
    assert_equal Date.new(2020, 12, 25), christmas
    assert_equal Date.new(2021, 9, 1), next_year_start
    assert_equal Date.new(2020, 9, 1), start_of_term
    assert_equal Date.new(2020, 12, 25), end_of_term

    travel_back
  end

  test "at christmas" do
    travel_to Time.zone.local(2021, 12, 25, 3, 7, 23)

    assert_equal Date.new(2021, 9, 1), start_of_year
    assert_equal Date.new(2021, 12, 25), christmas
    assert_equal Date.new(2022, 9, 1), next_year_start
    assert_equal Date.new(2021, 9, 1), start_of_term
    assert_equal Date.new(2021, 12, 25), end_of_term

    travel_back
  end

  test "get year shorthand" do
    travel_to Time.zone.local(2023, 11, 1, 7, 53, 24)

    assert_equal "23/24", academic_year_shorthand
  end

  test "date_to_academic_year" do
    { Date.new(2023, 9, 1) => 2023, Date.new(2023, 12, 25) => 2023,
      Date.new(2023, 1, 1) => 2022, Date.new(2023, 8, 31) => 2022 }.each do |date, year|
      assert_equal year, date_to_academic_year(date), date
    end
  end

  test "format_academic_year formats year correctly" do
    assert_equal "23/24", format_academic_year(2023)
    assert_equal "99/00", format_academic_year(1999)
    assert_equal "09/10", format_academic_year(2009)
  end

  test "format_years_active_label" do
    {
      [] => "no activity on record",
      nil => "no activity on record",
      [ 2023 ] => "active 23/24",
      [ 2019, 2020, 2021 ] => "active 19/20-21/22",
      [ 2017, 2018, 2019, 2022, 2023 ] => "active 17/18-19/20, 22/23-23/24",
      [ 2015, 2018, 2019, 2023 ] => "active 15/16, 18/19-19/20, 23/24"
    }.each do |years, label|
      assert_equal label, format_years_active_label(years), years.inspect
    end
  end

  private

  # Both the February and July cases fall within the 2019/20 academic year and
  # must report identical boundary dates.
  def assert_2019_20_academic_year
    assert_equal Date.new(2019, 9, 1), start_of_year
    assert_equal Date.new(2019, 12, 25), christmas
    assert_equal Date.new(2020, 9, 1), next_year_start
    assert_equal Date.new(2019, 12, 25), start_of_term
    assert_equal Date.new(2020, 9, 1), end_of_term
  end
end
