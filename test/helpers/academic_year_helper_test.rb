require 'test_helper'

class AcademicYearHelperTest < ActionView::TestCase
  test 'february' do
    travel_to Time.new(2020, 2, 2, 1, 4, 44)

    assert_equal Date.new(2019, 9, 1), start_of_year
    assert_equal Date.new(2019, 12, 25), christmas
    assert_equal Date.new(2020, 9, 1), next_year_start
    assert_equal Date.new(2019, 12, 25), start_of_term
    assert_equal Date.new(2020, 9, 1), end_of_term
  end

  test 'july' do
    travel_to Time.new(2020, 7, 2, 1, 4, 44)

    assert_equal Date.new(2019, 9, 1), start_of_year
    assert_equal Date.new(2019, 12, 25), christmas
    assert_equal Date.new(2020, 9, 1), next_year_start
    assert_equal Date.new(2019, 12, 25), start_of_term
    assert_equal Date.new(2020, 9, 1), end_of_term
  end

  test 'october' do
    travel_to Time.new(2020, 10, 2, 1, 4, 44)

    assert_equal Date.new(2020, 9, 1), start_of_year
    assert_equal Date.new(2020, 12, 25), christmas
    assert_equal Date.new(2021, 9, 1), next_year_start
    assert_equal Date.new(2020, 9, 1), start_of_term
    assert_equal Date.new(2020, 12, 25), end_of_term
  end
end
