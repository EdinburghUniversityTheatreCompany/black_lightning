# The academic year runs from 1 September to 1 September,
# and is split in half by Christmas day.
module AcademicYearHelper
  # Returns the start of the Academic year, which is the last 1 September.
  def start_of_year
    d1 = Date.new(Date.current.year, 9, 1)
    return d1 if d1.past?

    return Date.new(Date.current.year - 1, 9, 1)
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
    return start_of_year.advance(years: 1)
  end

  # Returns the start of the current term, which is either 1 September or 25 December, whichever happened most recently.
  def start_of_term
    return christmas if christmas < Date.current

    return start_of_year
  end

  # Return the end of the current term, which is either 1 September or 25 December, depending on which comes up sooner.
  def end_of_term
    return christmas if christmas >= Date.current

    return next_year_start
  end

  # Returns the 2x/2y short0hand for the current year.
  def academic_year_shorthand
    return "#{start_of_year.strftime("%y")}/#{next_year_start.strftime("%y")}"
  end
end
