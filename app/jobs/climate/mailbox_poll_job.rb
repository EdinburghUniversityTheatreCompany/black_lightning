module Climate
  ##
  # Ingests Govee CSV exports emailed to the shared climate mailbox, through the
  # same CsvImport + ReadingIngest path as the upload screen.
  #
  # Assumes ONE Govee sensor (of any placement, active or not), because nothing
  # in Govee's export email identifies the device. See #sensor_for to extend it.
  class MailboxPollJob < ::ApplicationJob
    include ::ErrorReporting

    queue_as :default
    limits_concurrency key: "climate_mailbox_poll", duration: 10.minutes

    ConfigurationError = Class.new(StandardError)

    AMBIGUOUS_ALERT_KEY = "climate_mailbox_ambiguous_sensor".freeze
    CSV_EXTENSIONS = %w[.csv .txt].freeze
    CSV_CONTENT_TYPES = %w[text/csv application/csv text/plain].freeze

    # On a day the sensor never reached Govee's cloud, the export email carries
    # this instead of a CSV. It must be filed, or every poll fetches it again; the
    # dashboard's stale badge reports the gap.
    GOVEE_SENDER_DOMAIN = "@govee.com".freeze
    GOVEE_NO_DATA = "No data in the time period".freeze

    class_attribute :mailbox_builder,
                    default: -> { ::Graph::MailboxClient.new(mailbox: Settings.mailbox) }

    def perform
      unless Settings.mailbox_configured?
        Rails.logger.info("[climate] mailbox poll skipped: no climate mailbox configured")
        return
      end

      mailbox = mailbox_builder.call
      mailbox.unread_messages.each { |message| process_safely(mailbox, message) }
    rescue ::GraphAuth::AuthError => e
      # The credential is shared with every Graph integration, so stop the loop.
      log_and_notify("[climate] Graph credentials rejected: #{e.message}", e,
                     context: { source: "climate_mailbox_poll" })
    end

    private

    # Leaving it unread IS the retry: the next cycle picks it up again.
    def process_safely(mailbox, message)
      process(mailbox, message)
    rescue ::GraphAuth::AuthError
      raise
    rescue => e
      log_and_notify("[climate] mailbox message #{message.id} failed: #{e.message}", e,
                     context: { source: "climate_mailbox_poll", subject: message.subject })
    end

    def process(mailbox, message)
      return file_no_data_notice(mailbox, message) if govee_no_data?(message)

      attachments = csv_attachments(mailbox, message)
      return skip(message, "no CSV attachment") if attachments.empty?

      # Collected, not summed inline: #import returns nil for a skipped
      # attachment, and summing nil would raise a second, misleading failure.
      results = attachments.map { |attachment| import(message, attachment) }
      return if results.any?(&:nil?)

      imported = results.sum

      # The commit point: a crash before it only repeats an idempotent import.
      mailbox.mark_read_and_move(message.id, :processed)
      Rails.logger.info("[climate] imported #{imported} readings from #{message.subject.inspect}")
    end

    def govee_no_data?(message)
      message.from_address.end_with?(GOVEE_SENDER_DOMAIN) && message.body_text.include?(GOVEE_NO_DATA)
    end

    def file_no_data_notice(mailbox, message)
      mailbox.mark_read_and_move(message.id, :processed)
      Rails.logger.info("[climate] Govee had no data to export for #{message.subject.inspect}; filed it")
    end

    def csv_attachments(mailbox, message)
      mailbox.attachments(message.id).select do |attachment|
        CSV_CONTENT_TYPES.include?(attachment[:content_type].to_s.split(";").first&.strip) ||
          CSV_EXTENSIONS.include?(File.extname(attachment[:filename].to_s).downcase)
      end
    end

    # Returns the readings written, or nil to leave the message unread.
    def import(message, attachment)
      sensor = sensor_for(message, attachment)
      return skip(message, "could not tell which sensor it is from") if sensor.nil?

      parsed = CsvImport.new(attachment[:bytes])
      return skip(message, parsed.errors.to_sentence) unless parsed.valid?

      ReadingIngest.upsert_series!(sensor: sensor, rows: parsed.rows).written
    end

    def skip(message, reason)
      Rails.logger.warn("[climate] leaving #{message.subject.inspect} unread: #{reason}")
      nil
    end

    # Govee's export email identifies no device, so with several sensors there is
    # nothing to resolve on, and one wall's readings filed under another is
    # silent, plausible nonsense.
    #
    # THE EXTENSION POINT: give each sensor its own mailbox (or plus address) and
    # resolve on the recipient, or match a per-sensor string if Govee ever names
    # the device. Only this method changes.
    def sensor_for(_message, _attachment)
      candidates = Sensor.govee.to_a
      return candidates.first if candidates.one?

      warn_ambiguous if candidates.many?
      nil
    end

    # Deduped to once a day: a configuration state, not an incident. Without the
    # alert, unattributable mail piles up unread unnoticed.
    def warn_ambiguous
      return unless Rails.cache.write(AMBIGUOUS_ALERT_KEY, true, expires_in: 1.day, unless_exist: true)

      error = ConfigurationError.new(
        "#{Sensor.govee.count} climate sensors exist, and a Govee export names none of them, " \
        "so emailed readings cannot be attributed. Import them by hand, or see " \
        "Climate::MailboxPollJob#sensor_for."
      )
      log_and_notify("[climate] emailed export cannot be attributed", error,
                     context: { source: "climate_mailbox_poll" })
    end
  end
end
