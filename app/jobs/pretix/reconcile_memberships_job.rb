# frozen_string_literal: true

module Pretix
  ##
  # Nightly. Brings every pretix membership back in line with the website's
  # member roles.
  #
  # This job is what makes the sync CORRECT; the per-user triggers only make it
  # feel immediate. A missed trigger — and several paths cannot be hooked at all,
  # see docs/pretix/membership-sync.md — costs at most a day, never a wrong
  # answer. That is the whole reason it exists, so removing it in favour of
  # callbacks would quietly turn every unhookable path into a permanent one.
  class ReconcileMembershipsJob < ::ApplicationJob
    include ::ErrorReporting

    queue_as :default
    limits_concurrency key: "pretix_reconcile_memberships", duration: 30.minutes

    # Injection seam for tests, as Climate::OutdoorPollJob takes its client.
    class_attribute :sync_builder, default: -> { MembershipSync.new }

    def perform
      return unless Settings.configured?

      counts = sync_builder.call.reconcile_all
      Rails.logger.info("Pretix membership reconcile: #{counts.inspect}")

      # The pass counter is the tell for the pagination hazard: pretix orders
      # memberships by -date_end, so patching one shifts every later page. One
      # pass means the shop was already settled; hitting the cap means it never
      # converged and rows may still be stale.
      warn_if_unconverged(counts)
      counts
    rescue Client::AuthError => e
      # Fatal for every customer alike, and the token dying silently is how this
      # sync would rot without anyone noticing.
      log_and_notify("Pretix membership reconcile could not authenticate", e)
      raise
    end

    private

    def warn_if_unconverged(counts)
      return unless counts[:passes] >= MembershipSync::MAX_PASSES

      Rails.logger.warn("Pretix membership reconcile hit the #{MembershipSync::MAX_PASSES}-pass cap " \
                        "without settling: #{counts.inspect}")
    end
  end
end
