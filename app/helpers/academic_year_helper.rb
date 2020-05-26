module AcademicYearHelper
  def start_of_year
    d1 = Date.new(Date.current.year, 9, 1)
    return d1 if d1.past?

    return Date.new(Date.current.year - 1, 9, 1)
  end

  def christmas
    if Date.current.month >= 9
      Date.new(Date.current.year, 12, 25)
    else
      Date.new(Date.current.year - 1, 12, 25)
    end
  end

  def next_year_start
    d1 = Date.new(Date.current.year, 9, 1)
    return d1 unless d1.past?

    return Date.new(Date.current.year + 1, 9, 1)
  end

  def start_of_term
    return christmas unless christmas > Date.current

    return start_of_year
  end

  def end_of_term
    return christmas unless christmas < Date.current

    return next_year_start
  end
end
