# The academic year runs from 1 September to 1 September,
# and is split in half by Christmas day.
module AcademicYearHelper
  # Returns the start of the Academic year, which is the last 1 September.
  def start_of_year
    d1 = Date.new(Date.current.year, 9, 1)
    return d1 if d1.past?

    Date.new(Date.current.year - 1, 9, 1)
  end

  # Returns the date Christmas will fall on this Academic Year.
  def christmas
    if Date.current.month >= 9
      Date.new(Date.current.year, 12, 25)
    else
      Date.new(Date.current.year - 1, 12, 25)
    end
  end

  # Returns the start of the next academic year.
  def next_year_start
    start_of_year.advance(years: 1)
  end

  # Returns the start of the current term, which is either 1 September or 25 December, whichever happened most recently.
  def start_of_term
    return christmas if christmas < Date.current

    start_of_year
  end

  # Return the end of the current term, which is either 1 September or 25 December, depending on which comes up sooner.
  def end_of_term
    return christmas if christmas >= Date.current

    next_year_start
  end

  # Returns the 2x/2y shorthand for the current year.
  def academic_year_shorthand
    "#{start_of_year.strftime("%y")}/#{next_year_start.strftime("%y")}"
  end

  # Converts a date to its academic year start year.
  # E.g., October 2023 -> 2023 (part of 2023/24 academic year)
  #       August 2023 -> 2022 (part of 2022/23 academic year)
  def date_to_academic_year(date)
    date.month >= 9 ? date.year : date.year - 1
  end

  # Formats an academic year start year as a shorthand string.
  # E.g., 2023 -> "23/24"
  def format_academic_year(start_year)
    "#{start_year.to_s[-2..]}/#{(start_year + 1).to_s[-2..]}"
  end
end
