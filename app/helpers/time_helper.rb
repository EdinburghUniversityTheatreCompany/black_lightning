module TimeHelper
  # Time as in datetime
  def time_range_string(start_time, end_time, include_year, format = :long)
    return '' if start_time.nil? && end_time.nil?

    # Check if there is just one datetime provided or if the datetimes are the same
    if start_time.nil? || end_time.nil? || start_time == end_time
      time = start_time || end_time
      result = I18n.l(time, format: format)
      result << " #{time.year}" if include_year

      return result
    end

    # Not at the same time, but maybe on the same date?
    if start_time.to_date == end_time.to_date
      result = I18n.l(start_time, format: :time_only)
    else
      result = I18n.l(start_time, format: format)
      result << " #{start_time.year}" if include_year && start_time.year != end_time.year
    end

    result << " - #{I18n.l(end_time, format: format)}"
    result << " #{end_time.year}" if include_year

    return result
  end

  def max_end_year
    return Date.current.year + 5
  end
end
