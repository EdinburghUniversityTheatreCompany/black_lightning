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
      log_and_notify("[climate] outdoor poll failed for #{sensor.display_name}: #{e.message}", e,
                     context: { source: "climate_outdoor_poll", sensor_id: sensor.id })
    end

    def poll(sensor)
      rows = client_builder.call(sensor).hourly_series(latitude: sensor.latitude.to_f,
                                                       longitude: sensor.longitude.to_f)
      ReadingIngest.upsert_series!(sensor: sensor, rows: rows)
      sensor.update_columns(last_polled_at: Time.current, last_error: nil)
    end
  end
end
