require 'test_helper'

class TimeHelperTest < ActionView::TestCase
  setup do
    @start_date = Date.new(2020, 5, 15)
  end

  test 'without proper start date' do
    assert_equal 'Friday 15 May 2020', time_range_string(nil, @start_date, true)
  end

  test 'without proper end date' do
    assert_equal 'Friday 15 May', time_range_string(@start_date, nil, false)
  end

  test 'without proper start or end date' do
    assert_equal '', time_range_string(nil, nil, false)
  end

  test 'with equal start and end date' do
    assert_equal 'Friday 15 May', time_range_string(@start_date, @start_date, false)
    assert_equal 'Friday 15 May 2020', time_range_string(@start_date, @start_date, true)
  end

  test 'with different start and end date' do
    end_date = @start_date.advance(days: 1)

    assert_equal 'Friday 15 May - Saturday 16 May', time_range_string(@start_date, end_date, false)
    assert_equal 'Friday 15 May - Saturday 16 May 2020', time_range_string(@start_date, end_date, true)

    year_later = end_date.advance(years: 1)

    assert_equal 'Friday 15 May 2020 - Sunday 16 May 2021', time_range_string(@start_date, year_later, true)
  end

  test 'with different start and end date, with different format' do
    end_date = @start_date.advance(days: 3)

    assert_equal 'May 15 - May 18', time_range_string(@start_date, end_date, false, :short)
    assert_equal 'May 15 - May 18 2020', time_range_string(@start_date, end_date, true, :short)
  end

  test 'with time on different dates' do
    start_time = DateTime.new(2020, 5, 15, 15, 17)
    end_time = start_time.advance(years: 1)

    assert_equal '15:17 Friday 15 May - 15:17 Saturday 15 May', time_range_string(start_time, end_time, false)
    assert_equal '15:17 Friday 15 May 2020 - 15:17 Saturday 15 May 2021', time_range_string(start_time, end_time, true)
  end

  test 'with time on same day' do
    start_time = DateTime.new(2020, 5, 15, 15, 17)
    end_time = start_time.advance(hours: 1)

    assert_equal '15:17 - 16:17 Friday 15 May', time_range_string(start_time, end_time, false)
    assert_equal '15:17 - 16:17 Friday 15 May 2020', time_range_string(start_time, end_time, true)
  end
end
