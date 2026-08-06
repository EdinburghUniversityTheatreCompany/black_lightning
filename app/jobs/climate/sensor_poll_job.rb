module Climate
  ##
  # Reads every active Govee sensor's current state and stores it. This job IS
  # the history — the Govee API has no history endpoint, so anything it fails to
  # record is gone for good.
  #
  # Ten minutes cuts both ways: the H5179's cloud state only refreshes on that
  # cadence, so polling faster writes the same value twice against a quota that
  # is per Govee ACCOUNT (10,000/day), not per key. Three sensors is 432/day.
  class SensorPollJob < ::ApplicationJob
    include ::ErrorReporting

    queue_as :default
    # Under the 10-minute schedule so a stuck run can't block the next cycle,
    # over any plausible run time (a handful of small HTTP calls).
    limits_concurrency key: "climate_sensor_poll", duration: 9.minutes

    # Test seam. Write it on THIS class only and restore it in teardown —
    # class_attribute's writer defines a singleton on whatever receives it, so a
    # subclass assignment sticks for the rest of the process.
    class_attribute :client_builder, default: -> { GoveeClient.new }

    def perform
      unless Settings.govee_configured?
        Rails.logger.info("[climate] sensor poll skipped: no Govee API key configured")
        return
      end

      sensors = Sensor.active.govee.to_a
      return if sensors.empty?

      client = client_builder.call
      sensors.each { |sensor| poll_safely(sensor, client) }
      warn_if_quota_low(client)
    rescue GoveeClient::AuthError, GoveeClient::ConfigurationError => e
      # Every sensor shares the one key, so the rest of the list is pointless.
      log_and_notify("[climate] Govee credentials rejected: #{e.message}", e,
                     context: { source: "climate_sensor_poll" })
    end

    private

    # One sensor's failure must not cost the others their sample this cycle.
    def poll_safely(sensor, client)
      poll(sensor, client)
    rescue GoveeClient::AuthError, GoveeClient::ConfigurationError
      raise
    rescue => e
      record_failure(sensor, e.message)
      log_and_notify("[climate] poll failed for #{sensor.display_name}: #{e.message}", e,
                     context: { source: "climate_sensor_poll", sensor_id: sensor.id })
    end

    def poll(sensor, client)
      unless sensor.unit_verified?
        # Not an error — it waits on an operator, and alerting every ten
        # minutes would be noise. The dashboard shows it in amber.
        Rails.logger.info("[climate] #{sensor.display_name} skipped: temperature unit not verified")
        record_failure(sensor, "Temperature unit not verified")
        return
      end

      state = client.state(sku: sensor.sku, external_id: sensor.external_id)

      unless state.online
        # Govee serves the last known value forever once the batteries die,
        # which would draw a flat, entirely fictional line.
        Rails.logger.info("[climate] #{sensor.display_name} skipped: Govee reports it offline")
        record_failure(sensor, "Govee reports the device offline")
        return
      end

      ReadingIngest.record_govee!(sensor: sensor, raw_temperature: state.raw_temperature,
                                  relative_humidity: state.relative_humidity, at: state.fetched_at)
      sensor.update_columns(last_polled_at: Time.current, last_error: nil)
    end

    def record_failure(sensor, message)
      sensor.update_columns(last_polled_at: Time.current, last_error: message.to_s.truncate(500))
    end

    # The cap is per account, so a second integration on this key drains it
    # with no other warning.
    def warn_if_quota_low(client)
      return unless client.respond_to?(:rate_limit_low?) && client.rate_limit_low?

      Rails.logger.warn("[climate] Govee daily quota low: #{client.rate_limit_remaining} requests left")
    end
  end
end
