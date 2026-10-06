# frozen_string_literal: true

module Pretix
  # Nightly. Brings every pretix membership back in line with the website's
  # member roles.
  #
  # This job is what makes the sync CORRECT; the per-user triggers only make it
  # immediate. Several paths cannot be hooked at all (see
  # docs/pretix/membership-sync.md), so replacing it with callbacks would turn
  # each of them into a permanent miss instead of a day's delay.
  class ReconcileMembershipsJob < ::ApplicationJob
    include ::ErrorReporting

    queue_as :default
    limits_concurrency key: "pretix_reconcile_memberships", duration: 30.minutes

    def perform
      return unless Settings.configured?

      counts = MembershipSync.new.reconcile_all
      Rails.logger.info("Pretix membership reconcile: #{counts.inspect}")

      # Hitting the pass cap means the run never settled and rows may still be stale.
      warn_if_unconverged(counts)
      counts
    rescue Client::AuthError => e
      # Fatal for every customer; a token dying silently is how this sync would rot.
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
