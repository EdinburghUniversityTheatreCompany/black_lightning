module DateHelper
  def date_range_string(start_date, end_date, include_year, format = :long)
    unless start_date.presence
      return
    end

    date = I18n.l(start_date, format: format)

    date << " #{start_date.year} " if include_year && (!end_date || start_date == end_date || start_date.year != end_date.year)

    if end_date && start_date != end_date
      date << ' - '
      date << I18n.l(end_date, format: format)

      date << " #{end_date.year}" if include_year
    end

    return date
  end
end
