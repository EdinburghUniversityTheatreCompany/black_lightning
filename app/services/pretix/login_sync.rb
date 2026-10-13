# frozen_string_literal: true

module Pretix
  # Fires a membership sync when someone authorises the PRETIX shop through
  # Doorkeeper, and only then. Signing in to the shop is the only moment we learn
  # a member has a pretix customer (pretix has no webhook for it), but Doorkeeper's
  # hook fires for every OAuth client the society runs.
  module LoginSync
    def self.call(controller)
      return unless Settings.configured?

      user = controller.send(:current_user)
      return if user.blank?
      return unless pretix_client?(controller.request.params[:client_id])

      # Deferred: on a FIRST login pretix creates the customer after this fires.
      SyncMembershipJob.set(wait: SyncMembershipJob::FIRST_LOGIN_DELAY).perform_later(user.id)
    end

    # Identified by redirect uri, not a stored uid: the uid is generated per environment.
    def self.pretix_client?(client_id)
      return false if client_id.blank?

      application = Doorkeeper::Application.find_by(uid: client_id)
      return false if application.blank?

      application.redirect_uri.to_s.include?(Settings::SHOP_HOST)
    end
  end
end
