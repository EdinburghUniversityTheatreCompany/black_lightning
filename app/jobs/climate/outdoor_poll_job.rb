module Climate
  ##
  # Fetches the outdoor comparison series hourly.
  #
  # Unlike the Govee job this one needs no credentials and cannot lose history:
  # it asks for a rolling window (past_days) and upserts the whole thing, so any
  # gap left by an outage fills itself on the next successful run. That is the
  # entire backfill strategy for outdoor data, and the reason Open-Meteo was
  # chosen over sources with a better uptime guarantee but no history.
  class OutdoorPollJob < ::ApplicationJob
    include ::ErrorReporting

    queue_as :default
    limits_concurrency key: "climate_outdoor_poll", duration: 5.minutes

    # How far behind the outdoor line has to fall before a failure is worth
    # reporting. Open-Meteo's free tier sheds load with the odd 503, and by the
    # self-heal above a failure costs nothing until it outlasts the window — so
    # only a feed that is actually DOWN is Honeybadger's business. Quieter
    # failures still reach last_error, which the dashboard's staleness badge
    # reads on its own tighter window (Sensor::STALE_AFTER).
    REPORT_FAILURE_AFTER = 1.day

    # Injection seam for tests. Takes the sensor so the source column picks the
    # client. See Climate::OUTDOOR_SOURCES.
    class_attribute :client_builder, default: ->(sensor) { Climate.outdoor_client_for(sensor.source) }

    def perform
      # Ensured rather than seeded by a data migration: test and CI databases
      # are schema-loaded, so a migration would never have run there.
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

    # Never having had a reading counts: the feed is no less missing for the
    # sensor being new.
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
