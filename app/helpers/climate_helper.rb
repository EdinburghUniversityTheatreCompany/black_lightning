module ClimateHelper
  def climate_temperature(value)
    return "—" if value.blank?

    "#{number_with_precision(value, precision: 1)} °C"
  end

  def climate_humidity(value)
    return "—" if value.blank?

    "#{number_with_precision(value, precision: 0)} %"
  end

  def climate_margin(value)
    return "—" if value.blank?

    "#{number_with_precision(value, precision: 1)} °C"
  end

  def climate_condensation_risk?(margin)
    margin.present? && margin < Climate::CONDENSATION_RISK_MARGIN
  end

  # "4 minutes ago", or an explicit nudge when there is nothing at all.
  def climate_last_seen(sensor)
    return "no readings yet" if sensor.latest_reading.nil?

    "#{time_ago_in_words(sensor.latest_reading.recorded_at)} ago"
  end

  def climate_tile_state(sensor)
    sensor.stale? ? :stale : :ok
  end

  CLIMATE_TILE_CLASSES = {
    stale: "border-amber-300 bg-amber-50/50",
    ok: "border-gray-200 bg-white"
  }.freeze

  def climate_tile_classes(state)
    CLIMATE_TILE_CLASSES.fetch(state, CLIMATE_TILE_CLASSES[:ok])
  end

  # Preset ranges as explicit from/to dates rather than a relative token, so a
  # copied link still means the same thing tomorrow.
  def climate_range_presets
    today = Date.current
    { "24 hours" => 1, "7 days" => 7, "30 days" => 30, "90 days" => 90, "1 year" => 365 }
      .transform_values { |days| { from: (today - (days - 1).days).iso8601, to: today.iso8601 } }
  end

  # Carries the ventilation selection through every link that changes the
  # range, so picking a sensor and then changing the dates does not silently
  # reset which sensor is on screen.
  #
  # The default is left OUT of the URL, the same way DateRange leaves the
  # default range out: a clean link keeps meaning "recent, coldest sensor".
  def climate_link_params(range_params, selected_key)
    return range_params if selected_key.blank? || selected_key == Climate::VentilationSeries::WORST

    range_params.merge(crypt: selected_key)
  end

  # The at-risk figures as a sentence, because the question that matters must
  # not depend on a chart rendering — the same reason the Now tiles are HTML.
  #
  # The denominator is hours WITH READINGS. "41 of 720 hours" would read as 6%
  # of a month when the hand-synced sensor covered six days of it.
  def climate_risk_sentence(summary)
    return "No readings in this range." if summary[:hours_with_readings].zero?

    threshold = number_with_precision(Climate::CONDENSATION_RISK_MARGIN, precision: 1)
    covered = pluralize(summary[:hours_with_readings], "hour")

    return "None of the #{covered} with readings came under #{threshold} °C of margin." if summary[:hours_at_risk].zero?

    percentage = (100.0 * summary[:hours_at_risk] / summary[:hours_with_readings]).round
    [ "#{summary[:hours_at_risk]} of the #{covered} with readings (#{percentage}%) " \
      "were under #{threshold} °C of margin.",
      climate_spell_sentence(summary) ].compact_blank.join(" ")
  end

  def climate_spell_sentence(summary)
    return nil if summary[:longest_spell_hours].to_i.zero?

    ended = summary[:longest_spell_ended_at]
    "The longest unbroken spell was #{pluralize(summary[:longest_spell_hours], 'hour')}" \
      "#{", ending #{ended.strftime('%-d %B %Y, %H:%M')}" if ended}."
  end
end
