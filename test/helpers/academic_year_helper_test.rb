require "test_helper"

class AcademicYearHelperTest < ActionView::TestCase
  test "february" do
    travel_to Time.zone.local(2020, 2, 2, 1, 4, 44)

    assert_equal Date.new(2019, 9, 1), start_of_year
    assert_equal Date.new(2019, 12, 25), christmas
    assert_equal Date.new(2020, 9, 1), next_year_start
    assert_equal Date.new(2019, 12, 25), start_of_term
    assert_equal Date.new(2020, 9, 1), end_of_term

    travel_back
  end

  test "july" do
    travel_to Time.zone.local(2020, 7, 2, 1, 4, 44)

    assert_equal Date.new(2019, 9, 1), start_of_year
    assert_equal Date.new(2019, 12, 25), christmas
    assert_equal Date.new(2020, 9, 1), next_year_start
    assert_equal Date.new(2019, 12, 25), start_of_term
    assert_equal Date.new(2020, 9, 1), end_of_term

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
end
