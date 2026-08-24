module DisplayHelper
  # "Tue 3 Mar", or "Tue 3 - Sat 7 Mar" when both ends share a month.
  def display_date_range(event)
    starts = event.start_date
    ends   = event.end_date

    return starts.strftime("%a %-d %b") if starts == ends
    return "#{starts.strftime('%a %-d')} – #{ends.strftime('%a %-d %b')}" if starts.month == ends.month

    "#{starts.strftime('%a %-d %b')} – #{ends.strftime('%a %-d %b')}"
  end

  # What to print in the "when" column. For an event that plays intermittently
  # the raw range is useless on a screen -- "Sep 1 - Jun 30" tells nobody when
  # to turn up -- so name the night instead.
  def display_when(event, on: Date.current)
    wdays = event.performance_wdays

    return display_date_range(event) if wdays.empty?
    return "Every #{Date::DAYNAMES[wdays.first]}" if wdays.one?

    occurrence = event.next_occurrence(on)
    occurrence ? occurrence.strftime("%a %-d %b") : display_date_range(event)
  end
end
