# frozen_string_literal: true

module Pretix
  # Keeps every event with pretix performance sync ticked in step with its
  # series: dates, end and admission times, and sold-out state.
  #
  # Every 15 minutes because a house can sell out in an afternoon; the one read per
  # on-sale show is trivial against pretix's 300/minute budget.
  #
  # See docs/superpowers/specs/2026-08-31-pretix-performance-sync-design.md.
  class SyncPerformancesJob < ::ApplicationJob
    include ::ErrorReporting

    queue_as :default
    limits_concurrency key: "pretix_sync_performances", duration: 15.minutes

    class_attribute :sync_builder, default: -> { PerformanceSync.new }

    def perform
      return unless Settings.configured?

      sync = sync_builder.call

      Event.pretix_performance_sync_due.find_each { |event| sync_safely(sync, event) }
    end

    private

    def sync_safely(sync, event)
      result = sync.call(event)
      log(event, result)
    rescue Client::AuthError => e
      # Fatal for every event; a token dying silently is how this sync would rot.
      log_and_notify("Pretix performance sync could not authenticate", e,
                     context: { source: "pretix_sync_performances" })
      raise
    rescue => e
      # A wrong slug is one producer's typo: letting it out would cost every other
      # show its sync for the same fifteen minutes.
      log_and_notify("Pretix performance sync failed for #{event.pretix_slug}", e,
                     context: { source: "pretix_sync_performances", event_id: event.id })
    end

    def log(event, result)
      # Not a failure: no series yet. PerformanceSync recorded it for the admin
      # page, so there is nothing to say here every fifteen minutes.
      return if result.missing_series?

      # A producer can empty a series on purpose, but it is also what a slug
      # pointing at a bare series looks like, so it is never silent.
      if result.emptied_series?
        Rails.logger.warn("Pretix performance sync removed every synced performance from " \
                          "#{event.pretix_slug}; check the slug if that was not intended")
      end

      return unless result.any_change?

      Rails.logger.info("Pretix performance sync #{event.pretix_slug}: #{result.to_h.inspect}")
    end
  end
end
