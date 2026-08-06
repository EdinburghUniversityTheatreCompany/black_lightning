module Climate
  ##
  # Ingests Govee CSV exports emailed to the shared climate mailbox, so a daily
  # scheduled export lands on the charts without anyone uploading it.
  #
  # It calls exactly the same CsvImport + ReadingIngest path as the manual
  # upload screen, so the two cannot drift.
  #
  # Assumes ONE crypt sensor, because nothing in Govee's export email identifies
  # the device. See #sensor_for for how to extend it.
  class MailboxPollJob < ::ApplicationJob
    include ::ErrorReporting

    queue_as :default
    limits_concurrency key: "climate_mailbox_poll", duration: 10.minutes

    ConfigurationError = Class.new(StandardError)

    AMBIGUOUS_ALERT_KEY = "climate_mailbox_ambiguous_sensor".freeze
    CSV_EXTENSIONS = %w[.csv .txt].freeze
    CSV_CONTENT_TYPES = %w[text/csv application/csv text/plain].freeze

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
      # The credential is shared with every other Graph integration, so there is
      # no point working through the rest of the messages.
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
      attachments = csv_attachments(mailbox, message)
      return skip(message, "no CSV attachment") if attachments.empty?

      # Collected, not summed inline: #import returns nil for an attachment it
      # could not handle, and summing that raises, which the rescue upstream would
      # then report as a second, misleading failure.
      results = attachments.map { |attachment| import(message, attachment) }
      return if results.any?(&:nil?)

      imported = results.sum

      # The commit point. The import is idempotent, so a crash before this costs
      # nothing worse than a repeated no-op next cycle.
      mailbox.mark_read_and_move(message.id, :processed)
      Rails.logger.info("[climate] imported #{imported} readings from #{message.subject.inspect}")
    end

    def csv_attachments(mailbox, message)
      mailbox.attachments(message.id).select do |attachment|
        CSV_CONTENT_TYPES.include?(attachment[:content_type].to_s.split(";").first&.strip) ||
          CSV_EXTENSIONS.include?(File.extname(attachment[:filename].to_s).downcase)
      end
    end

    # Returns the number of readings written, or nil when the message could not
    # be attributed. nil leaves the message unread for a human to sort out.
    def import(message, attachment)
      sensor = sensor_for(message, attachment)
      return skip(message, "could not tell which sensor it is from") if sensor.nil?

      # +String#dup+ first: force_encoding mutates its receiver, and Graph hands
      # back a frozen string, so calling it directly raises FrozenError, which the
      # per-message rescue would swallow into "left unread" forever.
      parsed = CsvImport.new(attachment[:bytes].to_s.dup.force_encoding(Encoding::UTF_8))
      return skip(message, parsed.errors.to_sentence) unless parsed.valid?

      ReadingIngest.upsert_series!(sensor: sensor, rows: parsed.rows).written
    end

    def skip(message, reason)
      Rails.logger.warn("[climate] leaving #{message.subject.inspect} unread: #{reason}")
      nil
    end

    # Govee's export email identifies no device, not in the subject and not in the
    # filename. So with several sensors there is nothing to resolve on, and one
    # wall's readings filed under another is silent, plausible nonsense.
    #
    # THE EXTENSION POINT: give each sensor its own mailbox (or plus address) and
    # resolve on the recipient, or add a per-sensor match string if Govee ever
    # names the device. Only this method changes.
    def sensor_for(_message, _attachment)
      candidates = Sensor.govee.to_a
      return candidates.first if candidates.one?

      warn_ambiguous if candidates.many?
      nil
    end

    # Otherwise unattributable mail piles up unread with nobody the wiser.
    # Deduped to once a day: it is a configuration state, not an incident.
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
