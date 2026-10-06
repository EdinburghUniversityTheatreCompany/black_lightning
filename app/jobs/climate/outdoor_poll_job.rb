module Climate
  ##
  # Fetches the outdoor comparison series hourly. It asks for a rolling window
  # and upserts all of it, so an outage gap fills itself on the next run (see
  # OpenMeteoClient).
  class OutdoorPollJob < ::ApplicationJob
    include ::ErrorReporting

    queue_as :default
    limits_concurrency key: "climate_outdoor_poll", duration: 5.minutes

    # Open-Meteo's free tier sheds load with the odd 503, and the next poll
    # re-serves the window, so a failure costs nothing until it outlasts it. Only
    # a feed DOWN this long is Honeybadger's business; every failure still reaches
    # last_error, which the dashboard's staleness badge reads.
    REPORT_FAILURE_AFTER = 1.day

    # Test seam. The sensor's source picks the client (Climate::OUTDOOR_SOURCES).
    class_attribute :client_builder, default: ->(sensor) { Climate.outdoor_client_for(sensor.source) }

    def perform
      Sensor.outdoor_source!

      Sensor.active.outdoor.find_each { |sensor| poll_safely(sensor) }
    end

    private

    def poll_safely(sensor)
      poll(sensor)
    rescue => e
      sensor.update_columns(last_polled_at: Time.current, last_error: e.message.to_s.truncate(500))
      record_failure(sensor, e)
    end

    def record_failure(sensor, error)
      message = "[climate] outdoor poll failed for #{sensor.display_name}: #{error.message}"
      latest = sensor.latest_reading

      return Rails.logger.warn(message) unless missing_for_a_day?(latest)

      log_and_notify(message, error,
                     context: { source: "climate_outdoor_poll", sensor_id: sensor.id,
                                latest_reading_at: latest&.recorded_at })
    end

    # Never having had a reading counts as missing.
    def missing_for_a_day?(latest)
      latest.nil? || latest.recorded_at < REPORT_FAILURE_AFTER.ago
    end

    def poll(sensor)
      rows = client_builder.call(sensor).hourly_series(latitude: sensor.latitude.to_f,
                                                       longitude: sensor.longitude.to_f)
      ReadingIngest.upsert_series!(sensor: sensor, rows: rows)
      sensor.update_columns(last_polled_at: Time.current, last_error: nil)
    end
  end
end
