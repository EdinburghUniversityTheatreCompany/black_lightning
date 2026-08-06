module Climate
  ##
  # Ingests Govee CSV exports emailed to the shared climate mailbox, so a daily
  # scheduled export lands on the charts without anyone uploading it.
  #
  # It calls exactly the same CsvImport + ReadingIngest path as the manual
  # upload screen, so the two cannot drift.
  #
  # WHICH SENSOR a file belongs to is the hard part: the CSV carries no device
  # identifier. The rule is deliberately conservative — match a sensor whose
  # display name appears in the subject or the attachment filename, and if
  # exactly one Govee sensor exists overall, use it. Anything ambiguous is left
  # UNREAD and reported rather than guessed at, because attributing the north
  # wall's readings to the south wall is silent, plausible-looking nonsense.
  class MailboxPollJob < ::ApplicationJob
    include ::ErrorReporting

    queue_as :default
    limits_concurrency key: "climate_mailbox_poll", duration: 10.minutes

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

    # One bad message must not stop the others being ingested. Leaving it unread
    # is the retry: the next cycle picks it up again.
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

      imported = attachments.sum { |attachment| import(message, attachment) }
      return if imported.nil?

      # Marking read is the commit point: an unread message is retried, and the
      # import itself is idempotent, so a crash between here and the move costs
      # nothing worse than a duplicate no-op next cycle.
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
    # be attributed — nil leaves the message unread for a human to sort out.
    def import(message, attachment)
      sensor = sensor_for(message, attachment)
      return skip(message, "could not tell which sensor it is from") if sensor.nil?

      # +String#dup+ first: force_encoding mutates its receiver, and Graph hands
      # back a frozen string, so calling it directly raises FrozenError — which
      # the per-message rescue would swallow into "left unread" forever.
      parsed = CsvImport.new(attachment[:bytes].to_s.dup.force_encoding(Encoding::UTF_8))
      return skip(message, parsed.errors.to_sentence) unless parsed.valid?

      ReadingIngest.upsert_series!(sensor: sensor, rows: parsed.rows).written
    end

    def skip(message, reason)
      Rails.logger.warn("[climate] leaving #{message.subject.inspect} unread: #{reason}")
      nil
    end

    def sensor_for(message, attachment)
      candidates = Sensor.govee.to_a
      return nil if candidates.empty?

      haystack = "#{message.subject} #{attachment[:filename]}".downcase
      named = candidates.select { |sensor| haystack.include?(sensor.display_name.downcase) }
      return named.first if named.one?
      return nil if named.many?

      # No name matched. With a single sensor there is nothing to confuse it
      # with; with several, guessing would be worse than waiting.
      candidates.one? ? candidates.first : nil
    end
  end
end
