# frozen_string_literal: true

module Pretix
  ##
  # One person's membership, straight after a login, an import or a role change.
  # Purely for immediacy — ReconcileMembershipsJob is what guarantees the answer
  # is right, so this job may fail, be skipped, or never be enqueued at all
  # without anything ending up permanently wrong.
  #
  # That is why nothing here retries and why a failure is logged rather than
  # raised: a raise would put it back on the queue to make the same call again
  # for a person the nightly run is about to fix anyway.
  class SyncMembershipJob < ::ApplicationJob
    include ::ErrorReporting

    queue_as :default

    # Injection seam for tests, as Climate::OutdoorPollJob takes its client. An
    # ActiveJob is instantiated by the queue, so there is no constructor to pass
    # a fake through.
    class_attribute :sync_builder, default: -> { MembershipSync.new }

    # A member's pretix customer account does not exist until they have logged
    # in at least once, and on that first login pretix creates it AFTER our
    # authorization response — so a sync fired the instant we authorize finds
    # nothing. Waiting lets the token exchange finish.
    FIRST_LOGIN_DELAY = 1.minute

    def self.enqueue_for(user_ids)
      ids = Array(user_ids).compact.uniq
      return if ids.empty? || !Settings.configured?

      ids.each { |id| perform_later(id) }
    end

    def perform(user_id)
      return unless Settings.configured?

      user = User.find_by(id: user_id)
      return if user.blank?

      sync_builder.call.sync_user(user)
    rescue Client::Error => e
      # Deliberately swallowed. See the class comment: the nightly reconcile is
      # the correctness mechanism, so one person's immediate sync failing is a
      # delay, not a defect, and retrying it here would hammer a shop that is
      # already returning errors.
      log_and_notify("Pretix membership sync failed for user #{user_id}", e, context: { user_id: user_id })
    end
  end
end
