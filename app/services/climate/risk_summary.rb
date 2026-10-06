module Climate
  ##
  # How much of the range the crypt spent close to condensing. Mould follows how
  # LONG the air sat near saturation, so the unit is the hour: hourly buckets
  # taking the worst margin inside each, counted as hours at risk, the longest
  # unbroken spell and a per-day tally for the bars.
  #
  # The denominator is hours WITH readings, never hours in the range: sensors
  # miss days, so "41 of 720 hours" reads as 6% of a month when it may be 8% of
  # the days covered.
  class RiskSummary
    def initialize(sensors:, range:)
      @sensors = Array(sensors)
      @range = range
      @colors = SeriesColors.new
    end

    # -> [{ id:, name:, color_index:, hours_with_readings:, hours_at_risk:,
    #       longest_spell_hours:, longest_spell_ended_at:,
    #       days: [{ date:, hours_with_readings:, at_risk_hours: }] }]
    def summaries
      # One query feeds the three counts and the bars, so they cannot disagree.
      hourly = Buckets.new(@range, seconds: Buckets::HOUR)
      grouped = MarginSeries.new(sensors: @sensors, range: @range, buckets: hourly).margins

      @sensors.map { |sensor| summarise(sensor, grouped.fetch(sensor.id, [])) }
    end

    private

    def summarise(sensor, hours)
      spell = longest_spell(hours)

      { id: sensor.id, name: sensor.display_name,
        color_index: @colors.index_for(sensor),
        hours_with_readings: hours.size,
        hours_at_risk: hours.count { |(_hour, margin)| at_risk?(margin) },
        longest_spell_hours: spell[:hours],
        longest_spell_ended_at: spell[:ended_at],
        days: by_day(hours) }
    end

    def at_risk?(margin) = margin < Climate::CONDENSATION_RISK_MARGIN

    # A missing hour BREAKS the run: a damp spell across a coverage hole was
    # never measured.
    def longest_spell(hours)
      best = { hours: 0, ended_at: nil }
      run = 0
      previous = nil

      hours.each do |(hour, margin)|
        run = if !at_risk?(margin)
                0
        elsif previous && (hour - previous) == Buckets::HOUR && run.positive?
                run + 1
        else
                1
        end
        best = { hours: run, ended_at: hour + Buckets::HOUR } if run > best[:hours]
        previous = hour
      end

      best
    end

    def by_day(hours)
      hours.group_by { |(hour, _margin)| hour.to_date }.map do |date, day_hours|
        { date: date,
          hours_with_readings: day_hours.size,
          at_risk_hours: day_hours.count { |(_hour, margin)| at_risk?(margin) } }
      end
    end
  end
end
