module ClimateHelper
  # Below this many degrees between the air temperature and its dew point,
  # condensation is a live risk rather than a theoretical one. This is the
  # number the crypt monitor exists to watch.
  CONDENSATION_RISK_MARGIN = 3.0

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
    margin.present? && margin < CONDENSATION_RISK_MARGIN
  end

  # "4 minutes ago", or an explicit nudge when there is nothing at all.
  def climate_last_seen(sensor)
    return "no readings yet" if sensor.latest_reading.nil?

    "#{time_ago_in_words(sensor.latest_reading.recorded_at)} ago"
  end

  # The tile's state, which drives both its styling and what it says. Ordered by
  # urgency: an unverified unit means the sensor is not recording at all, which
  # matters more than any reading being old.
  def climate_tile_state(sensor)
    return :unverified if sensor.govee? && !sensor.unit_verified?
    return :stale if sensor.stale?

    :ok
  end

  CLIMATE_TILE_CLASSES = {
    unverified: "border-amber-400 bg-amber-50",
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
end
