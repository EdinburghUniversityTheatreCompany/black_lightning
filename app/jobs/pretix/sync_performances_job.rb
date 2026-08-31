# frozen_string_literal: true

module Pretix
  ##
  # Keeps every event with pretix performance sync ticked in step with its
  # series: dates, end and admission times, and sold-out state.
  #
  # Every 15 minutes rather than nightly because the three date fields and the
  # availability field pull in opposite directions -- a curtain time changes
  # perhaps twice in a run, a house sells out in an afternoon. One job covering
  # both costs about one API read per on-sale show, trivial against pretix's
  # 300/minute budget, and leaves a single code path to reason about.
  #
  # See docs/superpowers/specs/2026-08-31-pretix-performance-sync-design.md.
  class SyncPerformancesJob < ::ApplicationJob
    include ::ErrorReporting

    queue_as :default
    limits_concurrency key: "pretix_sync_performances", duration: 15.minutes

    # Injection seams for tests, as Climate::OutdoorPollJob's client_builder is.
    # Named constants so a teardown can put the real ones back: assigning a bare
    # lambda by hand drops arguments, and class_attribute makes that stick for
    # the rest of the process.
    DEFAULT_SYNC_BUILDER = -> { PerformanceSync.new }

    class_attribute :sync_builder, default: DEFAULT_SYNC_BUILDER
    class_attribute :settings, default: Settings

    def perform
      return unless settings.configured?

      sync = sync_builder.call

      Event.pretix_performance_sync_due.find_each { |event| sync_safely(sync, event) }
    end

    private

    def sync_safely(sync, event)
      result = sync.call(event)
      log(event, result)
    rescue Client::AuthError => e
      # Fatal for every event alike, and a token dying silently is how this sync
      # would rot with nobody noticing.
      log_and_notify("Pretix performance sync could not authenticate", e,
                     context: { source: "pretix_sync_performances" })
      raise
    rescue => e
      # A wrong slug is one producer's typo. Letting it out would cost every
      # other show on the site its sync for the same fifteen minutes.
      log_and_notify("Pretix performance sync failed for #{event.pretix_slug}", e,
                     context: { source: "pretix_sync_performances", event_id: event.id })
    end

    def log(event, result)
      # Not a failure: pretix has no such series yet, which is what ticking the
      # box before building the shop looks like. PerformanceSync has recorded it
      # for the admin page; there is nothing to say here every fifteen minutes.
      return if result.missing_series?

      # An emptied series is a real thing a producer can do -- and it is also
      # exactly what a mis-set slug pointing at a bare series looks like, so it
      # is never silent.
      if result.emptied_series?
        Rails.logger.warn("Pretix performance sync removed every synced performance from " \
                          "#{event.pretix_slug}; check the slug if that was not intended")
      end

      return unless result.any_change?

      Rails.logger.info("Pretix performance sync #{event.pretix_slug}: #{result.to_h.inspect}")
    end
  end
end
