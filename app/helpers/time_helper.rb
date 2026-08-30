module TimeHelper
  # Time as in datetime
  def time_range_string(start_time, end_time, include_year, format = :long)
    return "" if start_time.nil? && end_time.nil?

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

    result
  end

  # "7.30pm", "8pm". British house style, and the minutes are dropped on the hour
  # rather than printing a bare ":00" that nobody says out loud.
  def short_time(time)
    return nil if time.blank?

    time.min.zero? ? time.strftime("%-l%P") : time.strftime("%-l.%M%P")
  end

  # "10am – 11pm", or just "7.30pm" when there is no end worth stating.
  #
  # Callers pass the EXPLICIT ends_at, never effective_ends_at: an end derived
  # from the running time would print "7.30pm – 9.45pm" on every line of a show,
  # which is noise. An occurrence that states its own end is saying something --
  # a Season's opening hours are exactly that, and the close is the half that
  # tells somebody when they have to be out.
  def time_span(from, to = nil)
    return nil if from.blank?
    return short_time(from) if to.blank?

    "#{short_time(from)} – #{short_time(to)}"
  end

  def max_end_year
    Date.current.year + 5
  end
end
