# frozen_string_literal: true

module Pretix
  # One person's membership, straight after a login, an import or a role change.
  # Purely for immediacy: ReconcileMembershipsJob guarantees the answer, so this
  # job may fail or never run without anything ending up permanently wrong. Hence
  # no retry, and a failure is logged rather than raised (a raise would requeue
  # the same call for someone the nightly run is about to fix anyway).
  class SyncMembershipJob < ::ApplicationJob
    include ::ErrorReporting

    queue_as :default

    class_attribute :sync_builder, default: -> { MembershipSync.new }

    # On a member's first login pretix creates the customer AFTER our authorization
    # response, so a sync fired the instant we authorize finds nothing.
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
      # Deliberately swallowed (see the class comment); retrying would also hammer
      # a shop that is already returning errors.
      log_and_notify("Pretix membership sync failed for user #{user_id}", e, context: { user_id: user_id })
    end
  end
end
