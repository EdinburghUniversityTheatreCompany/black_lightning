module Climate
  ##
  # How much of the range the crypt spent close to condensing.
  #
  # Mould is a function of how LONG the air sat near saturation, not of how low
  # the margin ever got, so the unit here is the hour: hourly buckets, each
  # taking the worst margin inside it, counted three ways — total hours at
  # risk, the longest unbroken spell, and a per-day tally for the bars.
  #
  # The denominator is hours that HAVE readings, never hours in the range. The
  # sensors are hand-synced over Bluetooth and routinely miss days, so
  # "41 of 720 hours" reads as 6% of a month when it may be 8% of the six days
  # actually covered.
  class RiskSummary
    HOUR = 3_600

    def initialize(sensors:, range:, threshold: Climate::CONDENSATION_RISK_MARGIN)
      @sensors = Array(sensors)
      @range = range
      @threshold = threshold
    end

    # -> [{ id:, name:, hours_with_readings:, hours_at_risk:,
    #       longest_spell_hours:, longest_spell_ended_at:,
    #       days: [{ date:, hours_with_readings:, at_risk_hours: }] }]
    def summaries
      grouped = hourly_margins

      @sensors.map { |sensor| summarise(sensor, grouped.fetch(sensor.id, [])) }
    end

    private

    # One query for every sensor and every figure below: the three counts and
    # the bars all have to agree, so they all come off the same rows.
    #
    # Written as literal Arel.sql calls, not built by interpolating a
    # constant: Brakeman flags an interpolated Arel.sql argument as a possible
    # SQL injection even when, as here, it can only ever come from a frozen
    # constant. See Climate::SeriesQuery for the same pattern.
    def hourly_margins
      return {} if @sensors.empty?

      Reading
        .where(sensor_id: @sensors.map(&:id), recorded_at: @range.starts_at..@range.ends_at)
        .where.not(temperature_c: nil).where.not(dew_point_c: nil)
        .group(:sensor_id, Arel.sql("DATE_SUB(recorded_at, INTERVAL (TIME_TO_SEC(TIME(recorded_at)) % 3600) SECOND)"))
        .order(Arel.sql("1 ASC, 2 ASC"))
        .pluck(:sensor_id,
               Arel.sql("DATE_SUB(recorded_at, INTERVAL (TIME_TO_SEC(TIME(recorded_at)) % 3600) SECOND)"),
               Arel.sql("MIN(temperature_c - dew_point_c)"))
        .group_by(&:first)
        .transform_values do |rows|
          rows.map { |(_sensor_id, hour, margin)| [ hour.in_time_zone, margin.to_f ] }
        end
    end

    def summarise(sensor, hours)
      spell = longest_spell(hours)

      { id: sensor.id, name: sensor.display_name,
        hours_with_readings: hours.size,
        hours_at_risk: hours.count { |(_hour, margin)| at_risk?(margin) },
        longest_spell_hours: spell[:hours],
        longest_spell_ended_at: spell[:ended_at],
        days: by_day(hours) }
    end

    def at_risk?(margin) = margin < @threshold

    # A missing hour BREAKS the run, the same way SeriesQuery refuses to draw a
    # line across an outage. Claiming thirty unbroken damp hours across a
    # twenty-hour hole is a measurement that never happened.
    def longest_spell(hours)
      best = { hours: 0, ended_at: nil }
      run = 0
      previous = nil

      hours.each do |(hour, margin)|
        run = if !at_risk?(margin)
                0
        elsif previous && (hour - previous) == HOUR && run.positive?
                run + 1
        else
                1
        end
        best = { hours: run, ended_at: hour + HOUR } if run > best[:hours]
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
